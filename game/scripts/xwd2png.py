#!/usr/bin/env python3
"""Convert XWD (X Window Dump) binary to PNG using PIL."""
from PIL import Image
import struct
import sys

def xwd_to_png(xwd_path, png_path):
    with open(xwd_path, 'rb') as f:
        data = f.read()
    
    # XWD header (big-endian integers)
    width = struct.unpack('>I', data[4:8])[0]
    height = struct.unpack('>I', data[8:12])[0]
    bytes_per_line = struct.unpack('>I', data[36:40])[0]
    
    # Visual info (colormap)
    vis_offset = struct.unpack('<I', data[40:44])[0]
    ncolors = struct.unpack('>I', data[44:48])[0] if vis_offset > 0 else 0
    data_offset = vis_offset + ncolors * 4
    
    pixel_data = data[data_offset:]
    
    # Build pixel array (XWD is ZPixMap: BGR, LSB-first)
    pixels = []
    for y in range(height):
        row = []
        for x in range(width):
            i = y * bytes_per_line + x * 3
            if i + 2 < len(pixel_data):
                b = pixel_data[i]
                g = pixel_data[i + 1]
                r = pixel_data[i + 2]
                row.append((r, g, b))
            else:
                row.append((0, 0, 0))
        pixels.append(row)
    
    img = Image.new('RGB', (width, height))
    for y in range(height):
        for x in range(width):
            img.putpixel((x, y), pixels[y][x])
    
    img.save(png_path)
    print(f"Converted {width}x{height} XWD -> PNG ({png_path})")

if __name__ == '__main__':
    if len(sys.argv) != 3:
        print("Usage: xwd2png.py <input.xwd> <output.png>")
        sys.exit(1)
    xwd_to_png(sys.argv[1], sys.argv[2])
