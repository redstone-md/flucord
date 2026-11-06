#include "capture_fit.h"

#include <iostream>

namespace {

int failures = 0;

void Expect(const char* what,
            flucord_video::FitRect actual,
            flucord_video::FitRect expected) {
  if (actual.left == expected.left && actual.top == expected.top &&
      actual.right == expected.right && actual.bottom == expected.bottom) {
    return;
  }
  ++failures;
  std::cerr << what << ": expected " << expected.left << "," << expected.top
            << " " << expected.right << "," << expected.bottom << ", got "
            << actual.left << "," << actual.top << " " << actual.right << ","
            << actual.bottom << "\n";
}

}  // namespace

int main() {
  // Worked by hand. A 16:10 window in a 720p stream: 720 high is 1152 wide,
  // which leaves 64 on each side.
  Expect("wide", flucord_video::FitInside(1600, 1000, 1280, 720),
         {64, 0, 1216, 720});
  // A tall window: 720 high is 360 wide, centred at 460.
  Expect("tall", flucord_video::FitInside(600, 1200, 1280, 720),
         {460, 0, 820, 720});
  // A 21:9 window: 1280 wide is 548.57 high, kept even at 548, with 86 above.
  Expect("letterboxed", flucord_video::FitInside(2560, 1097, 1280, 720),
         {0, 86, 1280, 634});
  // The stream's own shape fills it, and so does a source with no area.
  Expect("same shape", flucord_video::FitInside(1920, 1080, 1280, 720),
         {0, 0, 1280, 720});
  Expect("empty", flucord_video::FitInside(0, 0, 1280, 720),
         {0, 0, 1280, 720});
  return failures == 0 ? 0 : 1;
}
