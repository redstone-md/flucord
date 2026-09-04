#pragma once

#include <cstdint>

namespace flucord_video {

// Converts a QueryPerformanceCounter value to nanoseconds. Ticks must be
// non-negative and the frequency must be positive. The result stays monotonic
// for every value that fits in it.
std::int64_t QpcTicksToNanoseconds(std::int64_t ticks,
                                   std::int64_t ticks_per_second);

}  // namespace flucord_video
