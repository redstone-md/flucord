#pragma once

namespace flucord_video {

// A rectangle in picture elements, right and bottom exclusive.
struct FitRect {
  int left = 0;
  int top = 0;
  int right = 0;
  int bottom = 0;
};

// Where a source of `source_width` by `source_height` lands inside an output
// of `output_width` by `output_height`: as large as it fits, its shape kept,
// centred, with black bars on the two sides it does not fill. A window is
// rarely the shape of the stream, and stretching it would distort every
// letter in it.
//
// Every edge is even, because NV12 shares one chroma sample between two rows
// and two columns. A source with no area fills the whole output.
FitRect FitInside(int source_width,
                  int source_height,
                  int output_width,
                  int output_height);

}  // namespace flucord_video
