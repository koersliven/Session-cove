import os
from PIL import Image

def clean_transparency(image_path, output_path):
    print(f"Processing {image_path}...")
    img = Image.open(image_path).convert("RGBA")
    datas = img.getdata()

    new_data = []
    for item in datas:
        # Check for typical checkerboard gray colors or near-white
        # Common checkerboard grays: (204, 204, 204), (255, 255, 255), (128, 128, 128), (192, 192, 192)
        # We target pixels that are purely grayscale and not part of the character
        r, g, b, a = item
        
        # If it's a shade of gray and likely background
        # The octopus is coral/orange, headphones are blue/dark blue.
        # Gray pixels in the 'checkerboard' are usually very specific.
        is_gray = (r == g == b)
        is_background_gray = is_gray and (r in [128, 192, 204, 255])
        
        # Also check for the specific gray from the screenshot which looks like (204, 204, 204)
        if is_background_gray or (r == 204 and g == 204 and b == 204):
            new_data.append((0, 0, 0, 0))
        else:
            new_data.append(item)

    img.putdata(new_data)
    img.save(output_path, "PNG")
    print(f"Saved to {output_path}")

if __name__ == "__main__":
    resource_dir = "SessionCove/Resources"
    reference_dir = "reference"
    
    # Files to process
    files = [
        os.path.join(resource_dir, "claude_idle.png"),
        os.path.join(resource_dir, "claude_attention.png"),
        os.path.join(resource_dir, "claude_sleeping.png"),
        os.path.join(resource_dir, "claude_working.png"),
        os.path.join(reference_dir, "claude_wink.png")
    ]
    
    for f in files:
        if os.path.exists(f):
            clean_transparency(f, f)
        else:
            print(f"File not found: {f}")
