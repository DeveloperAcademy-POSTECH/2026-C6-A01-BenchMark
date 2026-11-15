"""Frame protection accepts normalized RGB scalars or NumPy channel arrays."""

def light_frame_guard(red, green, blue):
    # Cucumber green and its ink blends remain editable; neutral/warm frames stay.
    return ((red > .6) | (green > .6) | (blue > .6)) & (red > green * .82)


def dark_selfie_frame_guard(red, green, blue):
    return red > green * 1.01
