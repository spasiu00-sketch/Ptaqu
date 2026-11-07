class_name PowierzchniaKrokow
extends Resource
# Jedna powierzchnia, po której chodzi gracz. Tworzysz ją w Inspektorze gracza
# (grupa "Kroki - powierzchnie" -> Powierzchnie -> Nowy PowierzchniaKrokow).
#
# Powierzchnia jest rozpoznawana na dwa sposoby (wystarczy jeden):
#  - Id Tekstury: numer tekstury namalowanej w Terrain3D (kolejność z listy tekstur terenu, liczone od 0)
#  - Grupa: grupa węzła (StaticBody3D), na którym stoisz, np. podłoga w budynku (grupa "podloga_beton")
# Grupa ma pierwszeństwo przed teksturą terenu, dzięki temu podłogi w budynkach
# nadpisują teren, który może leżeć pod nimi.

@export var nazwa: String = "Powierzchnia"
@export var id_tekstury: int = -1                 # -1 = nie używaj (rozpoznawanie tylko po grupie)
@export var grupa: StringName = &""               # puste = nie używaj (rozpoznawanie tylko po teksturze)
@export var dzwieki: Array[AudioStream] = []
@export var glosnosc_db: float = 0.0              # korekta głośności tej powierzchni
