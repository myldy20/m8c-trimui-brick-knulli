// TrimUI Brick SDL3 audio route.
// A dedicated pump thread drains M8 USB capture and feeds Knulli playback.

#ifndef USE_LIBUSB

#include "audio.h"
#include <SDL3/SDL.h>

static SDL_AudioStream *audio_stream_in = NULL;
static SDL_AudioStream *audio_stream_out = NULL;
static SDL_Thread *audio_pump_thread = NULL;
static SDL_AtomicInt audio_pump_running = {0};
static SDL_AtomicInt audio_pump_paused = {0};
static unsigned int audio_initialized = 0;
static SDL_AudioSpec audio_spec_in = {SDL_AUDIO_S16LE, 2, 44100};

static int SDLCALL pump_audio(void *userdata) {
  (void)userdata;

  Uint8 temporary[8192];
  unsigned int read_errors = 0;
  unsigned int write_errors = 0;
  unsigned int startup_kicks = 0;
  bool received_audio = false;
  Uint64 silent_since = SDL_GetTicks();

  SDL_LogInfo(SDL_LOG_CATEGORY_AUDIO, "Brick audio pump thread started");

  while (SDL_GetAtomicInt(&audio_pump_running)) {
    if (SDL_GetAtomicInt(&audio_pump_paused)) {
      SDL_Delay(2);
      continue;
    }

    const int available = SDL_GetAudioStreamAvailable(audio_stream_in);
    if (available < 0) {
      if (read_errors++ < 5) {
        SDL_LogError(SDL_LOG_CATEGORY_AUDIO, "Cannot query M8 audio stream: %s", SDL_GetError());
      }
      SDL_Delay(2);
      continue;
    }

    if (available == 0) {
      const Uint64 now = SDL_GetTicks();
      if (!received_audio && startup_kicks < 3 && now - silent_since >= 1500) {
        startup_kicks++;
        SDL_LogWarn(SDL_LOG_CATEGORY_AUDIO,
                    "Brick audio startup is silent; restarting streams (%u/3)", startup_kicks);
        SDL_PauseAudioStreamDevice(audio_stream_in);
        SDL_PauseAudioStreamDevice(audio_stream_out);
        SDL_ClearAudioStream(audio_stream_in);
        SDL_ClearAudioStream(audio_stream_out);
        SDL_Delay(20);
        SDL_ResumeAudioStreamDevice(audio_stream_out);
        SDL_ResumeAudioStreamDevice(audio_stream_in);
        silent_since = SDL_GetTicks();
      }
      SDL_Delay(1);
      continue;
    }

    int remaining = available;
    while (remaining > 0 && SDL_GetAtomicInt(&audio_pump_running)) {
      const int requested = SDL_min(remaining, (int)sizeof(temporary));
      const int received = SDL_GetAudioStreamData(audio_stream_in, temporary, requested);
      if (received < 0) {
        if (read_errors++ < 5) {
          SDL_LogError(SDL_LOG_CATEGORY_AUDIO, "Cannot read M8 audio stream: %s", SDL_GetError());
        }
        break;
      }
      if (received == 0) {
        break;
      }

      if (!received_audio) {
        received_audio = true;
        SDL_LogInfo(SDL_LOG_CATEGORY_AUDIO,
                    "Brick audio capture active after %u startup restart(s)", startup_kicks);
      }

      if (!SDL_PutAudioStreamData(audio_stream_out, temporary, received)) {
        if (write_errors++ < 5) {
          SDL_LogError(SDL_LOG_CATEGORY_AUDIO, "Cannot queue speaker audio: %s", SDL_GetError());
        }
        break;
      }

      remaining -= received;
      read_errors = 0;
      write_errors = 0;
    }
  }

  SDL_LogInfo(SDL_LOG_CATEGORY_AUDIO, "Brick audio pump thread stopped");
  return 0;
}

void audio_toggle(const char *output_device_name, unsigned int audio_buffer_size) {
  if (!audio_initialized) {
    audio_initialize(output_device_name, audio_buffer_size);
    return;
  }

  const int paused = SDL_GetAtomicInt(&audio_pump_paused);
  if (paused) {
    SDL_ClearAudioStream(audio_stream_in);
    SDL_ClearAudioStream(audio_stream_out);
    SDL_ResumeAudioStreamDevice(audio_stream_out);
    SDL_ResumeAudioStreamDevice(audio_stream_in);
    SDL_SetAtomicInt(&audio_pump_paused, 0);
    SDL_Log("Audio resumed");
  } else {
    SDL_SetAtomicInt(&audio_pump_paused, 1);
    SDL_PauseAudioStreamDevice(audio_stream_in);
    SDL_PauseAudioStreamDevice(audio_stream_out);
    SDL_Log("Audio paused");
  }
}

int audio_initialize(const char *output_device_name, const unsigned int audio_buffer_size) {
  if (audio_initialized) {
    return 1;
  }

  if (!SDL_InitSubSystem(SDL_INIT_AUDIO)) {
    SDL_LogError(SDL_LOG_CATEGORY_AUDIO, "SDL audio init failed: %s", SDL_GetError());
    return 0;
  }

  SDL_LogInfo(SDL_LOG_CATEGORY_AUDIO, "SDL3 audio driver: %s", SDL_GetCurrentAudioDriver());

  int input_count = 0;
  int output_count = 0;
  SDL_AudioDeviceID m8_device_id = 0;
  SDL_AudioDeviceID output_device_id = 0;

  SDL_AudioDeviceID *input_devices = SDL_GetAudioRecordingDevices(&input_count);
  SDL_AudioDeviceID *output_devices = SDL_GetAudioPlaybackDevices(&output_count);

  if (input_devices == NULL || output_devices == NULL) {
    SDL_LogError(SDL_LOG_CATEGORY_AUDIO, "Cannot enumerate audio devices: %s", SDL_GetError());
    SDL_free(input_devices);
    SDL_free(output_devices);
    SDL_QuitSubSystem(SDL_INIT_AUDIO);
    return 0;
  }

  for (int index = 0; index < input_count; index++) {
    const char *name = SDL_GetAudioDeviceName(input_devices[index]);
    SDL_LogInfo(SDL_LOG_CATEGORY_AUDIO, "Recording device %d: %s", index,
                name != NULL ? name : "<unknown>");
    if (name != NULL && SDL_strstr(name, "M8") != NULL) {
      m8_device_id = input_devices[index];
    }
  }

  for (int index = 0; index < output_count; index++) {
    const char *name = SDL_GetAudioDeviceName(output_devices[index]);
    SDL_LogInfo(SDL_LOG_CATEGORY_AUDIO, "Playback device %d: %s", index,
                name != NULL ? name : "<unknown>");
    if (output_device_name != NULL && name != NULL &&
        SDL_strcasestr(name, output_device_name) != NULL) {
      output_device_id = output_devices[index];
    }
  }

  SDL_free(input_devices);
  SDL_free(output_devices);

  if (m8_device_id == 0) {
    SDL_LogError(SDL_LOG_CATEGORY_AUDIO, "Cannot find M8 recording device");
    SDL_QuitSubSystem(SDL_INIT_AUDIO);
    return 0;
  }

  if (output_device_id == 0) {
    output_device_id = SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK;
    SDL_LogInfo(SDL_LOG_CATEGORY_AUDIO, "Using default playback device");
  } else {
    SDL_LogInfo(SDL_LOG_CATEGORY_AUDIO, "Using requested playback device: %s",
                SDL_GetAudioDeviceName(output_device_id));
  }

  if (audio_buffer_size > 0) {
    char sample_frames[32];
    SDL_snprintf(sample_frames, sizeof(sample_frames), "%u", audio_buffer_size);
    SDL_SetHint(SDL_HINT_AUDIO_DEVICE_SAMPLE_FRAMES, sample_frames);
    SDL_LogInfo(SDL_LOG_CATEGORY_AUDIO, "Requested audio buffer: %u frames", audio_buffer_size);
  }

  SDL_AudioSpec output_spec = {SDL_AUDIO_S16LE, 2, 44100};
  int actual_output_frames = 0;
  if (!SDL_GetAudioDeviceFormat(output_device_id, &output_spec, &actual_output_frames)) {
    SDL_LogWarn(SDL_LOG_CATEGORY_AUDIO, "Cannot query playback format, using 44.1 kHz stereo: %s",
                SDL_GetError());
    output_spec = (SDL_AudioSpec){SDL_AUDIO_S16LE, 2, 44100};
  }

  audio_stream_out = SDL_OpenAudioDeviceStream(output_device_id, &output_spec, NULL, NULL);
  if (audio_stream_out == NULL) {
    SDL_LogError(SDL_LOG_CATEGORY_AUDIO, "Cannot open playback device: %s", SDL_GetError());
    SDL_QuitSubSystem(SDL_INIT_AUDIO);
    return 0;
  }

  audio_stream_in = SDL_OpenAudioDeviceStream(m8_device_id, &audio_spec_in, NULL, NULL);
  if (audio_stream_in == NULL) {
    SDL_LogError(SDL_LOG_CATEGORY_AUDIO, "Cannot open M8 recording device: %s", SDL_GetError());
    SDL_DestroyAudioStream(audio_stream_out);
    audio_stream_out = NULL;
    SDL_QuitSubSystem(SDL_INIT_AUDIO);
    return 0;
  }

  if (!SDL_SetAudioStreamFormat(audio_stream_in, &audio_spec_in, &output_spec)) {
    SDL_LogError(SDL_LOG_CATEGORY_AUDIO, "Cannot configure audio conversion: %s", SDL_GetError());
    SDL_DestroyAudioStream(audio_stream_in);
    SDL_DestroyAudioStream(audio_stream_out);
    audio_stream_in = NULL;
    audio_stream_out = NULL;
    SDL_QuitSubSystem(SDL_INIT_AUDIO);
    return 0;
  }

  SDL_LogInfo(SDL_LOG_CATEGORY_AUDIO,
              "Audio route ready: M8 44100 Hz stereo -> speaker %d Hz, %d channels, %d frames",
              output_spec.freq, output_spec.channels, actual_output_frames);

  SDL_SetAtomicInt(&audio_pump_paused, 0);
  SDL_SetAtomicInt(&audio_pump_running, 1);
  audio_pump_thread = SDL_CreateThread(pump_audio, "m8c-audio-pump", NULL);
  if (audio_pump_thread == NULL) {
    SDL_LogError(SDL_LOG_CATEGORY_AUDIO, "Cannot create audio pump thread: %s", SDL_GetError());
    SDL_SetAtomicInt(&audio_pump_running, 0);
    SDL_DestroyAudioStream(audio_stream_in);
    SDL_DestroyAudioStream(audio_stream_out);
    audio_stream_in = NULL;
    audio_stream_out = NULL;
    SDL_QuitSubSystem(SDL_INIT_AUDIO);
    return 0;
  }

  SDL_ResumeAudioStreamDevice(audio_stream_out);
  SDL_ResumeAudioStreamDevice(audio_stream_in);

  audio_initialized = 1;
  return 1;
}

void audio_close(void) {
  if (!audio_initialized) {
    return;
  }

  SDL_Log("Closing audio devices");

  SDL_SetAtomicInt(&audio_pump_running, 0);
  if (audio_pump_thread != NULL) {
    SDL_WaitThread(audio_pump_thread, NULL);
    audio_pump_thread = NULL;
  }

  SDL_PauseAudioStreamDevice(audio_stream_in);
  SDL_PauseAudioStreamDevice(audio_stream_out);
  SDL_DestroyAudioStream(audio_stream_in);
  SDL_DestroyAudioStream(audio_stream_out);

  audio_stream_in = NULL;
  audio_stream_out = NULL;
  audio_initialized = 0;
  SDL_SetAtomicInt(&audio_pump_paused, 0);

  SDL_QuitSubSystem(SDL_INIT_AUDIO);
}

#endif
