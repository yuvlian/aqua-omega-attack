package renderer

import "core:math"
import vk "vendor:vulkan"

Color :: struct {
	r, g, b, a: u8,
}

Vertex :: struct {
	pos:   [2]f32,
	uv:    [2]f32,
	color: [4]u8,
	// [mode, thickness]
	// mode 0 = atlas,
	// 1 = box outline,
	// 2 = circle fill,
	// 3 = circle outline
	shape: [2]f32,
}

MAX_VERTICES :: 131_072 // ~4x headroom over a 64-player worst case
MAX_INDICES  :: 196_608

Draw_State :: struct {
	vertex_data:  [^]Vertex,
	index_data:   [^]u32,
	vertex_count: u32,
	index_count:  u32,
}

draw_state: Draw_State
draw_begin :: proc () {
	draw_state.vertex_count = 0
	draw_state.index_count = 0
}

push_vertex :: proc (pos, uv: [2]f32, color: Color, shape: [2]f32 = {0, 0}) {
	if draw_state.vertex_count >= MAX_VERTICES {
		return
	}
	v := &draw_state.vertex_data[draw_state.vertex_count]
	v.pos = pos
	v.uv = uv
	v.color = {color.r, color.g, color.b, color.a}
	v.shape = shape
	draw_state.vertex_count += 1
}

push_triangle :: proc (a, b, c: u32) {
	if draw_state.index_count + 3 > MAX_INDICES {
		return
	}
	draw_state.index_data[draw_state.index_count + 0] = a
	draw_state.index_data[draw_state.index_count + 1] = b
	draw_state.index_data[draw_state.index_count + 2] = c
	draw_state.index_count += 3
}

push_quad :: proc (
	p0, p1, p2, p3, uv0, uv1, uv2, uv3: [2]f32,
	color: Color,
	shape: [2]f32 = {0, 0},
) {
	base := draw_state.vertex_count
	push_vertex(p0, uv0, color, shape)
	push_vertex(p1, uv1, color, shape)
	push_vertex(p2, uv2, color, shape)
	push_vertex(p3, uv3, color, shape)
	push_triangle(base + 0, base + 1, base + 2)
	push_triangle(base + 0, base + 2, base + 3)
}

draw_line :: proc (x0, y0, x1, y1, thickness: f32, color: Color) {
	dx := x1 - x0
	dy := y1 - y0
	length := math.sqrt(dx*dx + dy*dy)
	if length < 0.0001 {
		return
	}
	hx := -dy / length * thickness * 0.5
	hy := dx / length * thickness * 0.5
	wuv := font.white_uv
	push_quad(
		[2]f32 {x0 + hx, y0 + hy},
		[2]f32 {x0 - hx, y0 - hy},
		[2]f32 {x1 - hx, y1 - hy},
		[2]f32 {x1 + hx, y1 + hy},
		wuv, wuv, wuv, wuv, color,
	)
}

draw_rect_outline :: proc (x, y, w, h, thickness: f32, color: Color) {
	x1 := x + w
	y1 := y + h
	uv0 := [2]f32 {0, 0}
	uv1 := [2]f32 {1, 0}
	uv2 := [2]f32 {1, 1}
	uv3 := [2]f32 {0, 1}
	push_quad(
		[2]f32 {x, y}, [2]f32 {x1, y}, [2]f32 {x1, y1}, [2]f32 {x, y1},
		uv0, uv1, uv2, uv3,
		color,
		[2]f32 {1, thickness},
	)
}

draw_rect_filled :: proc (x, y, w, h: f32, color: Color) {
	wuv := font.white_uv
	push_quad(
		[2]f32 {x, y}, [2]f32 {x + w, y}, [2]f32 {x + w, y + h}, [2]f32 {x, y + h},
		wuv, wuv, wuv, wuv,
		color,
	)
}

draw_circle_outline :: proc (cx, cy, radius: f32, color: Color, thickness: f32 = 1) {
	x0 := cx - radius
	y0 := cy - radius
	x1 := cx + radius
	y1 := cy + radius
	uv0 := [2]f32 {0, 0}
	uv1 := [2]f32 {1, 0}
	uv2 := [2]f32 {1, 1}
	uv3 := [2]f32 {0, 1}
	push_quad(
		[2]f32 {x0, y0}, [2]f32 {x1, y0}, [2]f32 {x1, y1}, [2]f32 {x0, y1},
		uv0, uv1, uv2, uv3,
		color,
		[2]f32 {3, thickness},
	)
}

draw_circle_filled :: proc (cx, cy, radius: f32, color: Color) {
	x0 := cx - radius
	y0 := cy - radius
	x1 := cx + radius
	y1 := cy + radius
	uv0 := [2]f32 {0, 0}
	uv1 := [2]f32 {1, 0}
	uv2 := [2]f32 {1, 1}
	uv3 := [2]f32 {0, 1}
	push_quad(
		[2]f32 {x0, y0}, [2]f32 {x1, y0}, [2]f32 {x1, y1}, [2]f32 {x0, y1},
		uv0, uv1, uv2, uv3,
		color,
		[2]f32 {2, 0},
	)
}

draw_text :: proc (x, y: f32, text: string, scale: f32, color: Color) {
	pen_x := x
	pen_y := y
	for r in text {
		g := font_glyph(&font, r)
		if g.width > 0 && g.height > 0 {
			x0 := pen_x + g.x_offset*scale
			y0 := pen_y + g.y_offset*scale
			x1 := x0 + g.width*scale
			y1 := y0 + g.height*scale
			push_quad(
				[2]f32 {x0, y0},
				[2]f32 {x1, y0},
				[2]f32 {x1, y1},
				[2]f32 {x0, y1},
				[2]f32 {g.u0, g.v0},
				[2]f32 {g.u1, g.v0},
				[2]f32 {g.u1, g.v1},
				[2]f32 {g.u0, g.v1},
				color,
			)
		}
		pen_x += g.advance * scale
	}
}

draw_flush :: proc (r: ^Context) -> bool {
	cb := r.command_buffer
	r.vertex_count = draw_state.vertex_count
	r.index_count = draw_state.index_count

	if draw_state.index_count > 0 {
		vk.CmdBindPipeline(cb, .GRAPHICS, r.pipeline)
		vertex_offset := vk.DeviceSize(0)
		vk.CmdBindVertexBuffers(cb, 0, 1, &r.vertex_buffer, &vertex_offset)
		vk.CmdBindIndexBuffer(cb, r.index_buffer, 0, .UINT32)
		vk.CmdBindDescriptorSets(
			cb, .GRAPHICS, r.pipeline_layout, 0, 1, &r.descriptor_set, 0, nil)
		vk.CmdDrawIndexed(cb, draw_state.index_count, 1, 0, 0, 0)
	}

	vk.CmdEndRenderPass(cb)

	barrier := vk.ImageMemoryBarrier {
		image               = r.color_image,
		sType               = .IMAGE_MEMORY_BARRIER,
		srcAccessMask       = {.COLOR_ATTACHMENT_WRITE},
		dstAccessMask       = {.TRANSFER_READ},
		oldLayout           = .TRANSFER_SRC_OPTIMAL,
		newLayout           = .TRANSFER_SRC_OPTIMAL,
		srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		subresourceRange = vk.ImageSubresourceRange {
			aspectMask     = {.COLOR},
			baseMipLevel   = 0,
			levelCount     = 1,
			baseArrayLayer = 0,
			layerCount     = 1,
		},
	}

	vk.CmdPipelineBarrier(cb,
		{.COLOR_ATTACHMENT_OUTPUT}, {.TRANSFER}, {}, 0, nil, 0, nil, 1, &barrier)

	region := vk.BufferImageCopy {
		bufferOffset      = 0,
		bufferRowLength   = 0,
		bufferImageHeight = 0,
		imageSubresource = vk.ImageSubresourceLayers {
			aspectMask     = {.COLOR},
			mipLevel       = 0,
			baseArrayLayer = 0,
			layerCount     = 1,
		},
		imageOffset = vk.Offset3D {x = 0, y = 0, z = 0},
		imageExtent = vk.Extent3D {
			width  = r.extent.width,
			height = r.extent.height,
			depth  = 1,
		},
	}

	vk.CmdCopyImageToBuffer(cb,
		r.color_image, .TRANSFER_SRC_OPTIMAL, r.staging_buffer, 1, &region)

	vk.EndCommandBuffer(cb)

	submit := vk.SubmitInfo {
		sType              = .SUBMIT_INFO,
		commandBufferCount = 1,
		pCommandBuffers    = &cb,
	}

	return vk.QueueSubmit(r.queue, 1, &submit, r.fence) == .SUCCESS
}

find_memory_type :: proc (
	props: vk.PhysicalDeviceMemoryProperties,
	type_bits: u32,
	required: vk.MemoryPropertyFlags,
) -> u32 {
	for i in 0 ..< int(props.memoryTypeCount) {
		if (type_bits & (1 << uint(i))) == 0 {
			continue
		}
		if (props.memoryTypes[i].propertyFlags & required) == required {
			return u32(i)
		}
	}
	return 0
}

draw_pipeline_create :: proc (r: ^Context) -> bool {
	vert_module: vk.ShaderModule
	vert_ci := vk.ShaderModuleCreateInfo {
		sType    = .SHADER_MODULE_CREATE_INFO,
		codeSize = len(VERT_SHADER_SPIRV),
		pCode    = cast(^u32) raw_data(VERT_SHADER_SPIRV),
	}
	if vk.CreateShaderModule(r.device, &vert_ci, nil, &vert_module) != .SUCCESS {
		return false
	}
	defer vk.DestroyShaderModule(r.device, vert_module, nil)

	frag_module: vk.ShaderModule
	frag_ci := vk.ShaderModuleCreateInfo {
		sType    = .SHADER_MODULE_CREATE_INFO,
		codeSize = len(FRAG_SHADER_SPIRV),
		pCode    = cast(^u32) raw_data(FRAG_SHADER_SPIRV),
	}
	if vk.CreateShaderModule(r.device, &frag_ci, nil, &frag_module) != .SUCCESS {
		return false
	}
	defer vk.DestroyShaderModule(r.device, frag_module, nil)

	stages := [2]vk.PipelineShaderStageCreateInfo {
		{
			sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			stage  = {.VERTEX},
			module = vert_module,
			pName  = "main",
		},
		{
			sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			stage  = {.FRAGMENT},
			module = frag_module,
			pName  = "main",
		},
	}

	binding := vk.VertexInputBindingDescription {
		binding   = 0,
		stride    = u32(size_of(Vertex)),
		inputRate = .VERTEX,
	}

	attributes := [4]vk.VertexInputAttributeDescription {
		{location = 0, binding = 0, format = .R32G32_SFLOAT, offset = 0},
		{location = 1, binding = 0, format = .R32G32_SFLOAT, offset = 8},
		{location = 2, binding = 0, format = .R8G8B8A8_UNORM, offset = 16},
		{location = 3, binding = 0, format = .R32G32_SFLOAT, offset = 20},
	}
	vertex_input := vk.PipelineVertexInputStateCreateInfo {
		sType                           = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
		vertexBindingDescriptionCount   = 1,
		pVertexBindingDescriptions      = &binding,
		vertexAttributeDescriptionCount = len(attributes),
		pVertexAttributeDescriptions    = &attributes[0],
	}

	input_assembly := vk.PipelineInputAssemblyStateCreateInfo {
		sType                  = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
		topology               = .TRIANGLE_LIST,
		primitiveRestartEnable = false,
	}

	viewport_state := vk.PipelineViewportStateCreateInfo {
		sType         = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
		viewportCount = 1,
		scissorCount  = 1,
	}

	rasterizer := vk.PipelineRasterizationStateCreateInfo {
		sType                   = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
		depthClampEnable        = false,
		rasterizerDiscardEnable = false,
		polygonMode             = .FILL,
		cullMode                = {},
		frontFace               = .COUNTER_CLOCKWISE,
		depthBiasEnable         = false,
		lineWidth               = 1.0,
	}

	multisample := vk.PipelineMultisampleStateCreateInfo {
		sType                = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
		rasterizationSamples = {._1},
		sampleShadingEnable  = false,
	}

	depth_stencil := vk.PipelineDepthStencilStateCreateInfo {
		sType             = .PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
		depthTestEnable   = false,
		depthWriteEnable  = false,
		depthCompareOp    = .ALWAYS,
		stencilTestEnable = false,
	}

	blend_attachment := vk.PipelineColorBlendAttachmentState {
		blendEnable         = true,
		srcColorBlendFactor = .ONE,
		dstColorBlendFactor = .ONE_MINUS_SRC_ALPHA,
		colorBlendOp        = .ADD,
		srcAlphaBlendFactor = .ONE,
		dstAlphaBlendFactor = .ONE_MINUS_SRC_ALPHA,
		alphaBlendOp        = .ADD,
		colorWriteMask      = {.R, .G, .B, .A},
	}

	color_blend := vk.PipelineColorBlendStateCreateInfo {
		sType           = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
		logicOpEnable   = false,
		attachmentCount = 1,
		pAttachments    = &blend_attachment,
	}

	dynamic_states := [2]vk.DynamicState {.VIEWPORT, .SCISSOR}
	dynamic_state := vk.PipelineDynamicStateCreateInfo {
		sType             = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
		dynamicStateCount = len(dynamic_states),
		pDynamicStates    = &dynamic_states[0],
	}

	push_range := vk.PushConstantRange {
		stageFlags = {.VERTEX, .FRAGMENT},
		offset     = 0,
		size       = u32(size_of(Push_Constant)),
	}

	layout_ci := vk.PipelineLayoutCreateInfo {
		sType                  = .PIPELINE_LAYOUT_CREATE_INFO,
		setLayoutCount         = 1,
		pSetLayouts            = &r.descriptor_set_layout,
		pushConstantRangeCount = 1,
		pPushConstantRanges    = &push_range,
	}

	if vk.CreatePipelineLayout(r.device, &layout_ci, nil, &r.pipeline_layout) != .SUCCESS {
		return false
	}

	pipeline_ci := vk.GraphicsPipelineCreateInfo {
		sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
		stageCount          = 2,
		pStages             = &stages[0],
		pVertexInputState   = &vertex_input,
		pInputAssemblyState = &input_assembly,
		pViewportState      = &viewport_state,
		pRasterizationState = &rasterizer,
		pMultisampleState   = &multisample,
		pDepthStencilState  = &depth_stencil,
		pColorBlendState    = &color_blend,
		pDynamicState       = &dynamic_state,
		layout              = r.pipeline_layout,
		renderPass          = r.render_pass,
		subpass             = 0,
	}

	return vk.CreateGraphicsPipelines(
		r.device, 0, 1, &pipeline_ci, nil, &r.pipeline) == .SUCCESS
}

draw_pipeline_destroy :: proc (r: ^Context) {
	if r.pipeline != 0 {
		vk.DestroyPipeline(r.device, r.pipeline, nil)
		r.pipeline = 0
	}
	if r.pipeline_layout != 0 {
		vk.DestroyPipelineLayout(r.device, r.pipeline_layout, nil)
		r.pipeline_layout = 0
	}
}

draw_buffers_create :: proc (r: ^Context) -> bool {
	vertex_size := vk.DeviceSize(MAX_VERTICES * size_of(Vertex))
	index_size := vk.DeviceSize(MAX_INDICES * size_of(u32))

	vb_ci := vk.BufferCreateInfo {
		sType       = .BUFFER_CREATE_INFO,
		size        = vertex_size,
		usage       = {.VERTEX_BUFFER},
		sharingMode = .EXCLUSIVE,
	}
	if vk.CreateBuffer(r.device, &vb_ci, nil, &r.vertex_buffer) != .SUCCESS {
		return false
	}

	ib_ci := vk.BufferCreateInfo {
		sType       = .BUFFER_CREATE_INFO,
		size        = index_size,
		usage       = {.INDEX_BUFFER},
		sharingMode = .EXCLUSIVE,
	}
	if vk.CreateBuffer(r.device, &ib_ci, nil, &r.index_buffer) != .SUCCESS {
		return false
	}

	vb_req, ib_req: vk.MemoryRequirements
	vk.GetBufferMemoryRequirements(r.device, r.vertex_buffer, &vb_req)
	vk.GetBufferMemoryRequirements(r.device, r.index_buffer, &ib_req)

	props: vk.PhysicalDeviceMemoryProperties
	vk.GetPhysicalDeviceMemoryProperties(r.physical_device, &props)
	mem_type := find_memory_type(
		props, vb_req.memoryTypeBits, {.HOST_VISIBLE, .HOST_COHERENT})

	vb_alloc := vk.MemoryAllocateInfo {
		sType           = .MEMORY_ALLOCATE_INFO,
		allocationSize  = vb_req.size,
		memoryTypeIndex = mem_type,
	}
	ib_alloc := vk.MemoryAllocateInfo {
		sType           = .MEMORY_ALLOCATE_INFO,
		allocationSize  = ib_req.size,
		memoryTypeIndex = mem_type,
	}
	if vk.AllocateMemory(r.device, &vb_alloc, nil, &r.vertex_buffer_memory) != .SUCCESS {
		return false
	}
	if vk.AllocateMemory(r.device, &ib_alloc, nil, &r.index_buffer_memory) != .SUCCESS {
		return false
	}

	vk.BindBufferMemory(r.device, r.vertex_buffer, r.vertex_buffer_memory, 0)
	vk.BindBufferMemory(r.device, r.index_buffer, r.index_buffer_memory, 0)

	vdata, idata: rawptr
	if vk.MapMemory(r.device, r.vertex_buffer_memory, 0, vb_req.size, {}, &vdata) != .SUCCESS {
		return false
	}
	if vk.MapMemory(r.device, r.index_buffer_memory, 0, ib_req.size, {}, &idata) != .SUCCESS {
		return false
	}

	draw_state.vertex_data = cast([^]Vertex) vdata
	draw_state.index_data = cast([^]u32) idata
	draw_state.vertex_count = 0
	draw_state.index_count = 0
	return true
}

draw_buffers_destroy :: proc (r: ^Context) {
	if draw_state.vertex_data != nil {
		vk.UnmapMemory(r.device, r.vertex_buffer_memory)
		draw_state.vertex_data = nil
	}
	if draw_state.index_data != nil {
		vk.UnmapMemory(r.device, r.index_buffer_memory)
		draw_state.index_data = nil
	}
	if r.vertex_buffer_memory != 0 {
		vk.FreeMemory(r.device, r.vertex_buffer_memory, nil)
		r.vertex_buffer_memory = 0
	}
	if r.index_buffer_memory != 0 {
		vk.FreeMemory(r.device, r.index_buffer_memory, nil)
		r.index_buffer_memory = 0
	}
	if r.vertex_buffer != 0 {
		vk.DestroyBuffer(r.device, r.vertex_buffer, nil)
		r.vertex_buffer = 0
	}
	if r.index_buffer != 0 {
		vk.DestroyBuffer(r.device, r.index_buffer, nil)
		r.index_buffer = 0
	}
}
