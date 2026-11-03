// The C API in flucord_apm.h, over webrtc::AudioProcessing.

#include "flucord_apm.h"

#include <new>
#include <vector>

#include "api/audio/audio_processing.h"
#include "api/scoped_refptr.h"

// Calls on one processor are the caller's to keep apart; flucord_audio holds
// a lock around every one.
struct FlucordApm {
  rtc::scoped_refptr<webrtc::AudioProcessing> processing;

  // Where the library writes the render line back. It is never read, so it
  // is kept apart from the caller's buffer, which is const.
  std::vector<int16_t> render_out;
};

extern "C" {

FLUCORD_APM_EXPORT FlucordApm* flucord_apm_create(
    int32_t echo_cancellation,
    int32_t automatic_gain_control) {
  if (echo_cancellation == 0 && automatic_gain_control == 0) return nullptr;

  webrtc::AudioProcessing::Config config;
  config.high_pass_filter.enabled = true;
  config.echo_canceller.enabled = echo_cancellation != 0;
  config.echo_canceller.mobile_mode = false;
  config.gain_controller2.enabled = automatic_gain_control != 0;
  config.gain_controller2.adaptive_digital.enabled =
      automatic_gain_control != 0;
  config.noise_suppression.enabled = false;

  auto* apm = new (std::nothrow) FlucordApm();
  if (apm == nullptr) return nullptr;
  apm->processing = webrtc::AudioProcessingBuilder().SetConfig(config).Create();
  if (apm->processing == nullptr) {
    delete apm;
    return nullptr;
  }
  return apm;
}

FLUCORD_APM_EXPORT int32_t flucord_apm_process_render(FlucordApm* apm,
                                                      const int16_t* samples,
                                                      int32_t sample_rate,
                                                      int32_t channels) {
  if (apm == nullptr || samples == nullptr || channels <= 0) {
    return webrtc::AudioProcessing::kNullPointerError;
  }
  const webrtc::StreamConfig stream(sample_rate,
                                    static_cast<size_t>(channels));
  apm->render_out.resize(stream.num_samples());
  return apm->processing->ProcessReverseStream(samples, stream, stream,
                                               apm->render_out.data());
}

FLUCORD_APM_EXPORT int32_t flucord_apm_process_capture(FlucordApm* apm,
                                                       int16_t* samples,
                                                       int32_t sample_rate,
                                                       int32_t channels) {
  if (apm == nullptr || samples == nullptr || channels <= 0) {
    return webrtc::AudioProcessing::kNullPointerError;
  }
  const webrtc::StreamConfig stream(sample_rate,
                                    static_cast<size_t>(channels));
  return apm->processing->ProcessStream(samples, stream, stream, samples);
}

FLUCORD_APM_EXPORT void flucord_apm_destroy(FlucordApm* apm) { delete apm; }

}  // extern "C"
