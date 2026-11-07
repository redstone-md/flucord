#include "capture_fit.h"

#include <algorithm>
#include <cstdint>

namespace flucord_video {

FitRect FitInside(int source_width,
                  int source_height,
                  int output_width,
                  int output_height) {
  if (source_width <= 0 || source_height <= 0) {
    return {0, 0, output_width, output_height};
  }
  const auto even = [](std::int64_t value) {
    return static_cast<int>(std::max<std::int64_t>(2, value & ~1LL));
  };
  int width = output_width;
  int height = output_height;
  // Compared by cross-multiplying, so equal shapes fill exactly.
  if (static_cast<std::int64_t>(source_width) * output_height >=
      static_cast<std::int64_t>(output_width) * source_height) {
    height = std::min(output_height,
                      even(static_cast<std::int64_t>(source_height) *
                           output_width / source_width));
  } else {
    width = std::min(output_width,
                     even(static_cast<std::int64_t>(source_width) *
                          output_height / source_height));
  }
  const int left = ((output_width - width) / 2) & ~1;
  const int top = ((output_height - height) / 2) & ~1;
  return {left, top, left + width, top + height};
}

}  // namespace flucord_video
