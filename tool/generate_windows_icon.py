from pathlib import Path

from PIL import Image, ImageDraw


class FlucordIconGenerator:
    """Builds the deterministic Windows icon from Flucord design tokens."""

    CANVAS_SIZE = 1024
    ICON_SIZES = (16, 20, 24, 32, 40, 48, 64, 128, 256)

    def __init__(self, repository_root: Path) -> None:
        self._output_path = (
            repository_root / "windows" / "runner" / "resources" / "app_icon.ico"
        )

    def generate(self) -> None:
        canvas = Image.new(
            "RGBA",
            (self.CANVAS_SIZE, self.CANVAS_SIZE),
            (0, 0, 0, 0),
        )
        draw = ImageDraw.Draw(canvas)
        draw.rounded_rectangle(
            (56, 56, 968, 968),
            radius=184,
            fill="#101213",
        )
        draw.rounded_rectangle(
            (250, 212, 390, 812),
            radius=34,
            fill="#4c9b72",
        )
        draw.rounded_rectangle(
            (340, 212, 762, 352),
            radius=34,
            fill="#4c9b72",
        )
        draw.rounded_rectangle(
            (340, 436, 676, 576),
            radius=34,
            fill="#4c9b72",
        )
        draw.ellipse((720, 704, 814, 798), fill="#b87945")
        canvas.save(
            self._output_path,
            format="ICO",
            sizes=[(size, size) for size in self.ICON_SIZES],
        )


if __name__ == "__main__":
    FlucordIconGenerator(Path(__file__).resolve().parents[1]).generate()
