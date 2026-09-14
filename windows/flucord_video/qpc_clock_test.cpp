#include "qpc_clock.h"

#include <cstdint>
#include <iostream>

int main() {
  // At 10 MHz one tick is 100 ns. This counter value is the first one whose
  // intermediate product does not fit in int64_t. The expected value is a
  // worked example from the clock contract, not the production formula.
  constexpr std::int64_t ticks = 9223372037;
  constexpr std::int64_t ticks_per_second = 10000000;
  constexpr std::int64_t expected_nanoseconds = 922337203700;

  const std::int64_t actual =
      flucord_video::QpcTicksToNanoseconds(ticks, ticks_per_second);
  if (actual == expected_nanoseconds) return 0;

  std::cerr << "expected " << expected_nanoseconds << " ns, got " << actual
            << " ns\n";
  return 1;
}
