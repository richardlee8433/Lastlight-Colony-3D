class_name Meadow
## Large-scale meadow variation shared by the ground shader and the grass tufts, so lush,
## normal and dry patches line up: 0 = dry/yellowish, 0.5 = normal, 1 = lush/deep green.

const ORIGIN := Vector2(-40, -40)        # covers the map and the border forest
const SIZE_M := 80.0
const RES := 600                         # ~7.5 px per metre

static var _img: Image
static var _tex: ImageTexture

static func image() -> Image:
	if _img: return _img
	var n := FastNoiseLite.new()
	n.seed = 31
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 0.012          # in pixels: patches ~6-10 m across
	n.fractal_octaves = 3
	n.fractal_gain = 0.45
	_img = n.get_image(RES, RES, false, false, true)   # normalised to 0..1
	return _img

static func texture() -> ImageTexture:
	if _tex == null: _tex = ImageTexture.create_from_image(image())
	return _tex

## 0..1 lushness at a world point
static func sample(x: float, z: float) -> float:
	var img := image()
	var px := clampi(int((x - ORIGIN.x) / SIZE_M * RES), 0, RES - 1)
	var pz := clampi(int((z - ORIGIN.y) / SIZE_M * RES), 0, RES - 1)
	return img.get_pixel(px, pz).r

## grass colour for a lushness value
static func grass_color(l: float) -> Color:
	var dry := Color(0.60, 0.60, 0.24)
	var mid := Color(0.34, 0.55, 0.14)
	var lush := Color(0.20, 0.44, 0.10)
	return dry.lerp(mid, clampf(l * 2.0, 0.0, 1.0)) if l < 0.5 else mid.lerp(lush, clampf((l - 0.5) * 2.0, 0.0, 1.0))
