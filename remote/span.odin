package remote

import "core:mem"
import "core:reflect"
import "core:slice"
import "core:strconv"

Memory_Span :: struct {
	base_offset: int,
	total_bytes: int,
}

Copy_Op :: struct {
	src_offset: int,
	dst_offset: int,
	size:       int,
}

Layout_Plan :: struct {
	span:      Memory_Span,
	ops:       []Copy_Op,
	allocator: mem.Allocator,
}

plan_destroy :: proc (plan: Layout_Plan) {
	delete(plan.ops, plan.allocator)
}

Field_Loc :: struct {
	remote_offset: int,
	local_offset:  int,
	size:          int,
}

parse_field_tag :: proc (tag_str: string) -> (int, bool) {
	tag := tag_str
	if len(tag) == 0 {
		return 0, false
	}
	if len(tag) > 2 && tag[0] == '0' && tag[1] == 'x' {
		tag = tag[2:]
	}
	return strconv.parse_int(tag, 16)
}

get_struct_info :: proc (
	info: ^reflect.Type_Info,
	ctx: string,
) -> reflect.Type_Info_Struct {
	base_info := reflect.type_info_base(info)
	struct_info, ok := base_info.variant.(reflect.Type_Info_Struct)
	if !ok {
		panic(ctx)
	}
	return struct_info
}

walk_fields :: proc (
	info: ^reflect.Type_Info,
	remote_base: int,
	local_base: int,
	out: ^[dynamic]Field_Loc,
) {
	struct_info := get_struct_info(info, "walk_fields called on non-struct type")

	n := int(struct_info.field_count)
	types := struct_info.types[:n]
	tags := struct_info.tags[:n]
	offsets := struct_info.offsets[:n]

	prev_offset := -1

	for i in 0 ..< n {
		field_offset, ok := parse_field_tag(string(tags[i]))
		if !ok {
			continue
		}

		if field_offset < prev_offset {
			panic("make sure struct field tags are ascending!")
		}
		prev_offset = field_offset

		remote_offset := remote_base + field_offset
		local_offset := local_base + int(offsets[i])
		field_info := reflect.type_info_base(types[i])

		if _, is_struct := field_info.variant.(reflect.Type_Info_Struct); is_struct {
			walk_fields(types[i], remote_offset, local_offset, out)
		} else {
			append(out, Field_Loc {
				remote_offset = remote_offset,
				local_offset  = local_offset,
				size          = field_info.size,
			})
		}
	}
}

build_copy_plan :: proc ($T: typeid) -> Layout_Plan {
	locs := make([dynamic]Field_Loc, context.temp_allocator)
	walk_fields(type_info_of(T), 0, 0, &locs)

	lowest := max(int)
	highest := 0

	for l in locs {
		if l.remote_offset < lowest {
			lowest = l.remote_offset
		}
		if l.remote_offset + l.size > highest {
			highest = l.remote_offset + l.size
		}
	}

	if lowest == max(int) {
		lowest = 0
	}

	ops := make([dynamic]Copy_Op, len(locs))
	for l, i in locs {
		ops[i] = Copy_Op {
			src_offset = l.remote_offset - lowest,
			dst_offset = l.local_offset,
			size       = l.size,
		}
	}

	return Layout_Plan {
		span = Memory_Span {
			base_offset = lowest,
			total_bytes = highest - lowest,
		},
		ops       = ops[:],
		allocator = ops.allocator,
	}
}

apply_copy_plan :: proc (buffer: []u8, plan: Layout_Plan, $T: typeid) -> (T, Error) {
	dst: [size_of(T)]u8

	for op in plan.ops {
		// should never happen anyways
		when ODIN_DEBUG {
			if op.src_offset < 0 ||
				op.src_offset + op.size > len(buffer) ||
				op.dst_offset < 0 ||
				op.dst_offset + op.size > len(dst) {
				return {}, Error.Span_Failed
			}
		}

		copy(
			dst[op.dst_offset:op.dst_offset + op.size],
			buffer[op.src_offset:op.src_offset + op.size],
		)
	}

	if out, ok := slice.to_type(dst[:], T); ok {
		return out, Error.None
	}
	return {}, Error.Span_Failed
}
