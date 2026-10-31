#!/usr/bin/env python3

import io
import os
import struct
import sys

from PIL import Image, ImageDraw, ImageFilter


CANVAS = 2048
OUTPUT_SIZE = 1024


def scale(value: float) -> int:
    return round(value * CANVAS / OUTPUT_SIZE)


def hex_color(value: str, alpha: int = 255) -> tuple[int, int, int, int]:
    value = value.lstrip("#")
    return (
        int(value[0:2], 16),
        int(value[2:4], 16),
        int(value[4:6], 16),
        alpha,
    )


def interpolate_color(
    start: tuple[int, int, int, int],
    end: tuple[int, int, int, int],
    amount: float,
) -> tuple[int, int, int, int]:
    return tuple(
        round(start[index] + (end[index] - start[index]) * amount)
        for index in range(4)
    )


def vertical_gradient(
    stops: list[tuple[float, tuple[int, int, int, int]]],
) -> Image.Image:
    image = Image.new("RGBA", (CANVAS, CANVAS))
    draw = ImageDraw.Draw(image)

    for y in range(CANVAS):
        position = y / max(CANVAS - 1, 1)
        for index in range(len(stops) - 1):
            start_position, start_color = stops[index]
            end_position, end_color = stops[index + 1]
            if start_position <= position <= end_position:
                amount = (position - start_position) / max(
                    end_position - start_position,
                    0.0001,
                )
                color = interpolate_color(start_color, end_color, amount)
                draw.line((0, y, CANVAS, y), fill=color)
                break

    return image


def rounded_mask() -> Image.Image:
    mask = Image.new("L", (CANVAS, CANVAS), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle(
        (
            scale(92),
            scale(68),
            scale(932),
            scale(908),
        ),
        radius=scale(210),
        fill=255,
    )
    return mask


def make_cloud_mask() -> Image.Image:
    cloud = Image.new("L", (CANVAS, CANVAS), 0)
    draw = ImageDraw.Draw(cloud)

    draw.ellipse(
        (scale(270), scale(438), scale(566), scale(694)),
        fill=255,
    )
    draw.ellipse(
        (scale(382), scale(346), scale(688), scale(662)),
        fill=255,
    )
    draw.ellipse(
        (scale(526), scale(414), scale(780), scale(688)),
        fill=255,
    )
    draw.rounded_rectangle(
        (
            scale(304),
            scale(560),
            scale(744),
            scale(706),
        ),
        radius=scale(72),
        fill=255,
    )
    return cloud


def make_icon(render_size: int = CANVAS) -> Image.Image:
    canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    mask = rounded_mask()

    shadow = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    shadow_draw.rounded_rectangle(
        (
            scale(108),
            scale(92),
            scale(916),
            scale(932),
        ),
        radius=scale(205),
        fill=(2, 6, 26, 130),
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(scale(28)))
    canvas = Image.alpha_composite(canvas, shadow)

    background = vertical_gradient(
        [
            (0.0, hex_color("#07132F")),
            (0.30, hex_color("#152B72")),
            (0.62, hex_color("#334BE1")),
            (1.0, hex_color("#6A2BBB")),
        ]
    )

    halo = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    halo_draw = ImageDraw.Draw(halo)
    halo_draw.ellipse(
        (
            scale(476),
            scale(18),
            scale(1090),
            scale(634),
        ),
        fill=(69, 218, 255, 94),
    )
    halo_draw.ellipse(
        (
            scale(-180),
            scale(500),
            scale(470),
            scale(1110),
        ),
        fill=(188, 79, 255, 66),
    )
    halo = halo.filter(ImageFilter.GaussianBlur(scale(112)))
    background = Image.alpha_composite(background, halo)

    reflection = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    reflection_draw = ImageDraw.Draw(reflection)
    reflection_draw.polygon(
        [
            (scale(104), scale(312)),
            (scale(472), scale(68)),
            (scale(662), scale(68)),
            (scale(104), scale(616)),
        ],
        fill=(255, 255, 255, 26),
    )
    reflection = reflection.filter(ImageFilter.GaussianBlur(scale(38)))
    background = Image.alpha_composite(background, reflection)

    canvas.paste(background, (0, 0), mask)

    spotlight = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    spotlight_draw = ImageDraw.Draw(spotlight)
    spotlight_draw.ellipse(
        (
            scale(222),
            scale(228),
            scale(816),
            scale(822),
        ),
        fill=(94, 145, 255, 38),
    )
    spotlight = spotlight.filter(ImageFilter.GaussianBlur(scale(74)))
    canvas = Image.alpha_composite(
        canvas,
        Image.composite(
            spotlight,
            Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0)),
            mask,
        ),
    )

    cloud_mask = make_cloud_mask()
    cloud_shadow = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    cloud_shadow.paste((0, 5, 32, 118), (0, scale(24)), cloud_mask)
    cloud_shadow = cloud_shadow.filter(ImageFilter.GaussianBlur(scale(22)))
    canvas = Image.alpha_composite(canvas, cloud_shadow)

    cloud_fill = vertical_gradient(
        [
            (0.0, hex_color("#FFFFFF")),
            (0.48, hex_color("#F8FAFF")),
            (1.0, hex_color("#D5E0FA")),
        ]
    )
    canvas.paste(cloud_fill, (0, 0), cloud_mask)

    cloud_shade = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    shade_draw = ImageDraw.Draw(cloud_shade)
    shade_draw.rectangle(
        (0, scale(590), CANVAS, CANVAS),
        fill=(48, 77, 186, 34),
    )
    cloud_shade = cloud_shade.filter(ImageFilter.GaussianBlur(scale(34)))
    cloud_shade = Image.composite(
        cloud_shade,
        Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0)),
        cloud_mask,
    )
    canvas = Image.alpha_composite(canvas, cloud_shade)

    cloud_highlight = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    highlight_draw = ImageDraw.Draw(cloud_highlight)
    highlight_draw.ellipse(
        (
            scale(350),
            scale(367),
            scale(635),
            scale(505),
        ),
        fill=(255, 255, 255, 122),
    )
    cloud_highlight = cloud_highlight.filter(
        ImageFilter.GaussianBlur(scale(28))
    )
    cloud_highlight = Image.composite(
        cloud_highlight,
        Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0)),
        cloud_mask,
    )
    canvas = Image.alpha_composite(canvas, cloud_highlight)

    arrow = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    arrow_draw = ImageDraw.Draw(arrow)
    arrow_color = hex_color("#2949D8")
    arrow_width = scale(42)

    arrow_draw.line(
        (scale(512), scale(450), scale(512), scale(582)),
        fill=arrow_color,
        width=arrow_width,
    )
    arrow_draw.line(
        (
            scale(452),
            scale(526),
            scale(512),
            scale(592),
            scale(572),
            scale(526),
        ),
        fill=arrow_color,
        width=arrow_width,
        joint="curve",
    )
    arrow_draw.line(
        (scale(448), scale(655), scale(576), scale(655)),
        fill=arrow_color,
        width=scale(34),
    )

    arrow_shadow = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    arrow_shadow.paste((20, 32, 108, 60), (0, scale(7)), arrow.getchannel("A"))
    arrow_shadow = arrow_shadow.filter(ImageFilter.GaussianBlur(scale(8)))
    canvas = Image.alpha_composite(canvas, arrow_shadow)
    canvas = Image.alpha_composite(canvas, arrow)

    rim = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    rim_draw = ImageDraw.Draw(rim)
    rim_draw.rounded_rectangle(
        (
            scale(92),
            scale(68),
            scale(932),
            scale(908),
        ),
        radius=scale(210),
        outline=(255, 255, 255, 60),
        width=scale(3),
    )
    rim_draw.arc(
        (
            scale(110),
            scale(86),
            scale(914),
            scale(890),
        ),
        197,
        322,
        fill=(255, 255, 255, 92),
        width=scale(5),
    )
    canvas = Image.alpha_composite(canvas, rim)

    return canvas.resize(
        (render_size, render_size),
        Image.Resampling.LANCZOS,
    )


def write_icns(icon: Image.Image, output: str) -> None:
    chunks = [
        ("icp4", 16),
        ("icp5", 32),
        ("icp6", 64),
        ("ic07", 128),
        ("ic08", 256),
        ("ic09", 512),
        ("ic10", 1024),
        ("ic11", 32),
        ("ic12", 64),
        ("ic13", 256),
        ("ic14", 512),
    ]

    payload = bytearray()
    for chunk_type, size in chunks:
        png_buffer = io.BytesIO()
        icon.resize(
            (size, size),
            Image.Resampling.LANCZOS,
        ).save(
            png_buffer,
            "PNG",
            optimize=True,
        )
        png_data = png_buffer.getvalue()
        payload.extend(chunk_type.encode("ascii"))
        payload.extend(struct.pack(">I", len(png_data) + 8))
        payload.extend(png_data)

    with open(output, "wb") as file:
        file.write(b"icns")
        file.write(struct.pack(">I", len(payload) + 8))
        file.write(payload)


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: generate_icon.py OUTPUT.icns")

    output = os.path.abspath(sys.argv[1])
    os.makedirs(os.path.dirname(output), exist_ok=True)

    icon = make_icon(OUTPUT_SIZE)
    preview_path = os.path.join(
        os.path.dirname(output),
        "AppIcon-1024.png",
    )
    icon.save(preview_path, "PNG", optimize=True)
    write_icns(icon, output)


if __name__ == "__main__":
    main()
