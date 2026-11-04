class_name Niebo
extends Node3D
# Księżyc (klockowy, pikselowy, z poświatą i zimnym światłem) oraz chmury jak w Minecrafcie.
# Użycie: dodaj do sceny poziomu węzeł Node3D, przypisz ten skrypt. Resztę robi kod.
# Księżyc ma wyłączoną mgłę. Chmury mają własną mgłę w shaderze: kolor i gęstość biorą
# z WorldEnvironment (world_environment.gd), a całość jest przyciemniana suwakiem "Jasnosc".
# Księżyc jest rysowany w stałej odległości od kamery, więc nigdy się nie zbliża.
# Jeśli Camera3D ma małe "Far", zwiększ je (domyślnie 4000 wystarcza).

@export_group("Księżyc")
@export var ksiezyc_wlaczony: bool = true
@export_range(0.0, 360.0, 1.0) var ksiezyc_azymut: float = 200.0     # w którą stronę świata świeci
@export_range(5.0, 85.0, 1.0) var ksiezyc_wysokosc: float = 35.0     # kąt nad horyzontem
@export var ksiezyc_odleglosc: float = 350.0
@export var ksiezyc_rozmiar: float = 42.0
@export var ksiezyc_kolor: Color = Color(0.88, 0.92, 1.0)
@export var poswiata_rozmiar: float = 140.0
@export var poswiata_kolor: Color = Color(0.55, 0.68, 1.0)

@export_group("Księżyc - światło")
@export var swiatlo_wlaczone: bool = true
@export var swiatlo_kolor: Color = Color(0.55, 0.65, 0.95)
@export var swiatlo_energia: float = 0.35
@export var swiatlo_cienie: bool = true

@export_group("Chmury")
@export var chmury_wlaczone: bool = true
@export var chmury_wysokosc: float = 70.0
@export var chmury_rozmiar_klocka: float = 12.0     # szerokość i długość jednego klocka
@export var chmury_grubosc: float = 4.0
@export var chmury_promien: int = 14                # ile klocków od gracza w każdą stronę
@export_range(-1.0, 1.0, 0.01) var chmury_prog: float = 0.1   # wyżej = mniej chmur
@export var chmury_czestotliwosc: float = 0.12      # wyżej = drobniejsze chmury
@export var chmury_predkosc: float = 1.5            # jednostek na sekundę (kierunek +X)
@export var chmury_seed: int = 4
@export var chmury_kolor: Color = Color(0.30, 0.34, 0.46)
@export_range(0.0, 1.0, 0.01) var chmury_jasnosc: float = 0.3   # ogólne przyciemnienie chmur (0 = czarne, 1 = bez zmian)

@export_group("Chmury - mgła")
@export_range(0.0, 1.0, 0.05) var chmury_mgla_sila: float = 0.0      # ile maksymalnie chmura "wchodzi" w kolor mgły (0 = bez mgły)
@export var chmury_mgla_mnoznik: float = 0.35                          # ułamek gęstości mgły świata (większy = bardziej rozmyte)
@export var chmury_mgla_gestosc: float = 0.007                         # gęstość, gdy w scenie nie ma WorldEnvironment z mgłą
@export var chmury_mgla_kolor: Color = Color(0.70, 0.75, 0.80)         # kolor, gdy w scenie nie ma WorldEnvironment

const SHADER_CHMUR := """
shader_type spatial;
render_mode unshaded, fog_disabled, cull_back;

uniform vec4 kolor : source_color = vec4(0.3, 0.34, 0.46, 1.0);
uniform vec4 mgla_kolor : source_color = vec4(0.7, 0.75, 0.8, 1.0);
uniform float mgla_gestosc = 0.007;
uniform float mgla_sila : hint_range(0.0, 1.0) = 0.8;
uniform float jasnosc : hint_range(0.0, 1.0) = 0.3;

varying vec3 wn;

void vertex() {
	wn = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	// góra jasna, boki średnie, spód ciemny (jak w Minecrafcie)
	float k = mix(0.55, 1.0, wn.y * 0.5 + 0.5);
	vec3 col = kolor.rgb * k;

	// własna mgła: im dalej od kamery, tym bardziej kolor mgły (nigdy w 100%)
	float d = length(VERTEX);
	float f = (1.0 - exp(-d * mgla_gestosc)) * mgla_sila;
	col = mix(col, mgla_kolor.rgb, clamp(f, 0.0, 1.0));

	// całość przyciemniona, żeby chmury pasowały do ciemnej gry
	ALBEDO = col * jasnosc;
}
"""

var _kierunek: Vector3 = Vector3.UP
var _ksiezyc: MeshInstance3D
var _poswiata: MeshInstance3D
var _swiatlo: DirectionalLight3D

var _chmury: MultiMeshInstance3D
var _mat_chmur: ShaderMaterial
var _szum: FastNoiseLite
var _dryf: float = 0.0
var _przesuniecie: int = 0
var _bx: int = 0
var _bz: int = 0
var _przebudowa: bool = true
var _mgla_gotowa: bool = false


func _ready() -> void:
	_kierunek = _kierunek_ksiezyca()
	if ksiezyc_wlaczony:
		_zbuduj_ksiezyc()
	if chmury_wlaczone:
		_zbuduj_chmury()


func _kierunek_ksiezyca() -> Vector3:
	var az := deg_to_rad(ksiezyc_azymut)
	var el := deg_to_rad(ksiezyc_wysokosc)
	return Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el)).normalized()


# ---------- Księżyc ----------

func _zbuduj_ksiezyc() -> void:
	# tarcza: mały pikselowy obrazek, filtr "nearest" daje klockowy wygląd
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = _tekstura_ksiezyca()
	mat.albedo_color = ksiezyc_kolor
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.5
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.disable_fog = true

	var quad := QuadMesh.new()
	quad.size = Vector2(ksiezyc_rozmiar, ksiezyc_rozmiar)
	quad.material = mat

	_ksiezyc = MeshInstance3D.new()
	_ksiezyc.name = "Ksiezyc"
	_ksiezyc.mesh = quad
	_ksiezyc.top_level = true
	_ksiezyc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ksiezyc)

	# poświata wokół księżyca (dodawana do obrazu, tuż za tarczą)
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	grad.colors = PackedColorArray([
		Color(poswiata_kolor, 0.35), Color(poswiata_kolor, 0.0)])
	var tekstura_poswiaty := GradientTexture2D.new()
	tekstura_poswiaty.gradient = grad
	tekstura_poswiaty.fill = GradientTexture2D.FILL_RADIAL
	tekstura_poswiaty.fill_from = Vector2(0.5, 0.5)
	tekstura_poswiaty.fill_to = Vector2(1.0, 0.5)
	tekstura_poswiaty.width = 128
	tekstura_poswiaty.height = 128

	var mat_p := StandardMaterial3D.new()
	mat_p.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat_p.albedo_texture = tekstura_poswiaty
	mat_p.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat_p.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat_p.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat_p.disable_fog = true

	var quad_p := QuadMesh.new()
	quad_p.size = Vector2(poswiata_rozmiar, poswiata_rozmiar)
	quad_p.material = mat_p

	_poswiata = MeshInstance3D.new()
	_poswiata.name = "PoswiataKsiezyca"
	_poswiata.mesh = quad_p
	_poswiata.top_level = true
	_poswiata.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_poswiata)

	# zimne światło księżyca na scenie
	if swiatlo_wlaczone:
		_swiatlo = DirectionalLight3D.new()
		_swiatlo.name = "SwiatloKsiezyca"
		_swiatlo.light_color = swiatlo_kolor
		_swiatlo.light_energy = swiatlo_energia
		_swiatlo.shadow_enabled = swiatlo_cienie
		_swiatlo.top_level = true
		add_child(_swiatlo)
		# światło biegnie od księżyca ku światu
		_swiatlo.global_transform = Transform3D(
				Basis.looking_at(-_kierunek, Vector3.UP), Vector3.ZERO)


# Pikselowy księżyc 16x16: tarcza z ciemniejszymi "kraterami"
func _tekstura_ksiezyca() -> ImageTexture:
	var n := 16
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var srodek := Vector2((n - 1) * 0.5, (n - 1) * 0.5)
	for y in n:
		for x in n:
			var d := Vector2(x, y).distance_to(srodek)
			if d <= n * 0.5 - 0.5:
				var s := 1.0 - rng.randf() * 0.15
				if rng.randf() < 0.12:
					s -= 0.2
				img.set_pixel(x, y, Color(s, s, s, 1.0))
			else:
				img.set_pixel(x, y, Color(0.0, 0.0, 0.0, 0.0))
	return ImageTexture.create_from_image(img)


func _aktualizuj_ksiezyc(poz_kamery: Vector3) -> void:
	if _ksiezyc == null:
		return
	_ksiezyc.global_position = poz_kamery + _kierunek * ksiezyc_odleglosc
	if _poswiata != null:
		_poswiata.global_position = poz_kamery + _kierunek * (ksiezyc_odleglosc + 5.0)


# ---------- Chmury ----------

func _zbuduj_chmury() -> void:
	_szum = FastNoiseLite.new()
	_szum.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_szum.seed = chmury_seed
	_szum.frequency = chmury_czestotliwosc

	var shader := Shader.new()
	shader.code = SHADER_CHMUR
	_mat_chmur = ShaderMaterial.new()
	_mat_chmur.shader = shader
	_mat_chmur.set_shader_parameter("kolor", chmury_kolor)
	_mat_chmur.set_shader_parameter("mgla_kolor", chmury_mgla_kolor)
	_mat_chmur.set_shader_parameter("mgla_gestosc", chmury_mgla_gestosc)
	_mat_chmur.set_shader_parameter("mgla_sila", chmury_mgla_sila)
	_mat_chmur.set_shader_parameter("jasnosc", chmury_jasnosc)

	var klocek := BoxMesh.new()
	klocek.size = Vector3(chmury_rozmiar_klocka, chmury_grubosc, chmury_rozmiar_klocka)
	klocek.material = _mat_chmur

	var bok := chmury_promien * 2 + 1
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = klocek
	mm.instance_count = bok * bok
	mm.visible_instance_count = 0

	_chmury = MultiMeshInstance3D.new()
	_chmury.name = "Chmury"
	_chmury.multimesh = mm
	_chmury.top_level = true
	_chmury.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var duzo := float(chmury_promien + 2) * chmury_rozmiar_klocka
	_chmury.custom_aabb = AABB(Vector3(-duzo, -chmury_grubosc, -duzo),
			Vector3(duzo * 2.0, chmury_grubosc * 2.0, duzo * 2.0))
	add_child(_chmury)


# Kolor i gęstość mgły czytamy dopiero w pierwszej klatce, bo world_environment.gd
# ustawia mgłę w swoim _ready() i mógłby jeszcze nie zdążyć.
func _pobierz_mgle_swiata() -> void:
	_mgla_gotowa = true
	if _mat_chmur == null:
		return
	var scena := get_tree().current_scene
	if scena == null:
		return
	for w in scena.find_children("*", "WorldEnvironment", true, false):
		var env := (w as WorldEnvironment).environment
		if env != null and env.fog_enabled:
			_mat_chmur.set_shader_parameter("mgla_kolor", env.fog_light_color)
			_mat_chmur.set_shader_parameter("mgla_gestosc", env.fog_density * chmury_mgla_mnoznik)
			return


# Pole chmur chodzi za graczem, a wzór zależy od współrzędnych świata (szum),
# więc chmury nie "jadą" razem z graczem, tylko dryfują same.
func _aktualizuj_chmury(delta: float, poz_kamery: Vector3) -> void:
	if _chmury == null:
		return

	if not _mgla_gotowa:
		_pobierz_mgle_swiata()

	var klocek := maxf(chmury_rozmiar_klocka, 0.1)
	_dryf += chmury_predkosc * delta
	while _dryf >= klocek:
		_dryf -= klocek
		_przesuniecie += 1
		_przebudowa = true

	var bx := roundi(poz_kamery.x / klocek)
	var bz := roundi(poz_kamery.z / klocek)
	if bx != _bx or bz != _bz:
		_bx = bx
		_bz = bz
		_przebudowa = true

	if _przebudowa:
		_przebudowa = false
		_przebuduj_chmury(klocek)

	_chmury.global_position = Vector3(_bx * klocek + _dryf, chmury_wysokosc, _bz * klocek)


func _przebuduj_chmury(klocek: float) -> void:
	var mm := _chmury.multimesh
	var ile := 0
	for i in range(-chmury_promien, chmury_promien + 1):
		for j in range(-chmury_promien, chmury_promien + 1):
			var wx := _bx + i - _przesuniecie
			var wz := _bz + j
			if _szum.get_noise_2d(wx, wz) > chmury_prog:
				mm.set_instance_transform(ile,
						Transform3D(Basis.IDENTITY, Vector3(i * klocek, 0.0, j * klocek)))
				ile += 1
	mm.visible_instance_count = ile


# ---------- Pętla ----------

func _process(delta: float) -> void:
	var kamera := get_viewport().get_camera_3d()
	if kamera == null:
		return
	var poz := kamera.global_position
	_aktualizuj_ksiezyc(poz)
	_aktualizuj_chmury(delta, poz)
