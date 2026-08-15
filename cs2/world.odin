package cs2

MAX_CLIENTS :: 64
BONE_COUNT  :: 30 // skeleton bones read from the scene node

Bone :: struct {
	pos: [3]f32,
	pad: [20]u8,
}

Weapon :: struct {
	valid:      bool,
	item_index: u16,
	ammo:       i32,
	reloading:  bool,
	name:       string,
}

Player :: struct {
	name:            [128]u8,
	team:            u8,
	health:          i32,
	pos:             Vec3,
	alive:           bool,
	local:           bool,
	scoped:          bool,
	defusing:        bool,
	flashed:         bool,
	has_c4:          bool,
	pawn_handle:     uintptr,
	observer_target: u32,
	bones:           [BONE_COUNT]Vec3,
	bone_count:      int,
	weapon:          Weapon,
}

Bomb :: struct {
	planted: bool,
	carrier: uintptr, // pawn handle
	pos:     Vec3,
}

World :: struct {
	view_matrix:  Mat4,
	valid:        bool,
	local:        Player,
	local_index:  int, // -1 when none
	players:      [MAX_CLIENTS]Player,
	player_count: int,
	bomb:         Bomb,
}

BONE_CONNECTIONS :: [17][2]int {
	{1,   3}, // pelvis -> spine_1
	{3,   4}, // spine_1 -> spine_2
	{4,  23}, // spine_2 -> chest
	{23,  6}, // chest -> neck
	{6,   7}, // neck -> head

	{6,   9}, // neck -> shoulder_L
	{9,  10}, // shoulder_L -> elbow_L
	{10, 11}, // elbow_L -> hand_L

	{6,  13}, // neck -> shoulder_R
	{13, 14}, // shoulder_R -> elbow_R
	{14, 15}, // elbow_R -> hand_R

	{1,  17}, // pelvis -> hip_L
	{17, 18}, // hip_L -> knee_L
	{18, 19}, // knee_L -> foot_heel_L

	{1,  20}, // pelvis -> hip_R
	{20, 21}, // hip_R -> knee_R
	{21, 22}, // knee_R -> foot_heel_R
}

HEAD_BONE :: 7
