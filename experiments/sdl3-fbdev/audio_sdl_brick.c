// Brick-specific SDL3 audio bridge for the fbdev experiment.
// The upstream output callback did not drain the M8 capture stream reliably on
// Knulli's ALSA stack. Pump newly recorded data into the playback stream from
// the recording callback instead.

#ifndef USE_LIBUSB

#include "audio.h"
#include <SDL3/SDL.h>

static SDL_AudioStream *audio_stream_in = NULL;
static SDL_AudioStream *audio_stream_out = NULL;
static unsigned int audio_paused = 0;
static unsigned int audio_initialized = 0;
static SDL_AudioSpec audio_spec_in = {SDL_AUDIO_S16LE, 2, 44100};

static void SDLCALL audio_cb_in(void *userdata, SDL_AudioStream *stream, int additional_amount,
                                int total_amount) {
  (void)userdata;
  (void)additional_amount;
  (void)total_amount;

  if (audio_stream_out == NULL) {
    return;
  }

  Uint8 temporary[4096];
  for (;;) {
    const int available = SDL_GetAudioStreamAvailable(stream);
    if (available < 0) {
      SDL_LogError(SDL_LOG_CATEGORY_AUDIO, "Cannot query M8 audio data: %s", SDL_GetError());
      return;
    }
    if (available == 0) {
      return;
    }

    const int requested = SDL_min(available, (int)sizeof(temporary));
    const int received = SDL_GetAudioStreamData(stream, temporary, requested);
    if (received < 0) {
      SDL_LogError(SDL_LOG_CATEGORY_AUDIO, "Cannot read M8 audio data: %s", SDL_GetError());
      return;
    }
    if (received == 0) {
      return;
    }

    if (!SDL_PutAudioStreamData(audio_stream_out, temporary, received)) {
      SDL_LogError(SDL_LOG_CATEGORY_AUDIO, "Cannot queue speaker audio: %s", SDL_GetError());
      return;
    }
  }
}

void audio_toggle(const char *output_device_name, unsigned int audio_buffer_size) {
  if (!audio_initialized) {
    audio_initialize(output_device_name, audio_buffer_size);
    return;
  }

  if (audio_paused) {
    SDL_ResumeAudioStreamDevice(audio_stream_out);
    SDL_ResumeAudioStreamDevice(audio_stream_in);
  } else {
    SDL_PauseAudioStreamDevice(audio_stream_in);
    SDL_PauseAudioStreamDevice(audio_stream_out);
  }

  audio_paused = !audio_paused;
  SDL_Log(audio_paused ? "Audio paused" : "Audio resumed");
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

  audio_stream_in = SDL_OpenAudioDeviceStream(m8_device_id, &audio_spec_in, audio_cb_in, NULL);
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

  SDL_ResumeAudioStreamDevice(audio_stream_out);
  SDL_ResumeAudioStreamDevice(audio_stream_in);

  audio_paused = 0;
  audio_initialized = 1;
  return 1;
}

void audio_close(void) {
  if (!audio_initialized) {
    return;
  }

  SDL_Log("Closing audio devices");

  SDL_PauseAudioStreamDevice(audio_stream_in);
  SDL_PauseAudioStreamDevice(audio_stream_out);
  SDL_DestroyAudioStream(audio_stream_in);
  SDL_DestroyAudioStream(audio_stream_out);

  audio_stream_in = NULL;
  audio_stream_out = NULL;
  audio_initialized = 0;
  audio_paused = 0;

  SDL_QuitSubSystem(SDL_INIT_AUDIO);
}

#endif
