package renderer

import "core:c"
import "core:os"

import vk "vendor:vulkan"
import stbtt "vendor:stb/truetype"

ATLAS_SIZE   :: 1024
PIXEL_HEIGHT :: 16
GLYPH_PAD    :: 2

Glyph :: struct {
	u0, v0, u1, v1:          f32,
	width, height:           f32,
	x_offset, y_offset:      f32,
	advance:                 f32,
}

Font :: struct {
	atlas_image:   vk.Image,
	atlas_memory:  vk.DeviceMemory,
	atlas_view:    vk.ImageView,
	sampler:       vk.Sampler,
	glyphs:        map[rune]Glyph,
	info:          stbtt.fontinfo,
	font_data:     []byte,
	scale:         f32,
	size:          f32,
	ascent:        f32,
	descent:       f32,
	pixel_height:  f32,
	atlas_w:       int,
	atlas_h:       int,
	cursor_x:      int,
	cursor_y:      int,
	row_height:    int,
	row_pitch:     int,
	mapped:        rawptr,
	white_uv:      [2]f32,
	fallback:      Glyph,
	valid:         bool,
}

font: Font

transition_image_layout :: proc (
	r: ^Context,
	image: vk.Image,
	old_layout,
	new_layout: vk.ImageLayout,
) {
	alloc_info := vk.CommandBufferAllocateInfo {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool        = r.command_pool,
		level              = .PRIMARY,
		commandBufferCount = 1,
	}
	cb: vk.CommandBuffer
	vk.AllocateCommandBuffers(r.device, &alloc_info, &cb)

	begin := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = {.ONE_TIME_SUBMIT},
	}
	vk.BeginCommandBuffer(cb, &begin)

	barrier := vk.ImageMemoryBarrier {
		sType               = .IMAGE_MEMORY_BARRIER,
		srcAccessMask       = {.HOST_WRITE},
		dstAccessMask       = {.SHADER_READ},
		oldLayout           = old_layout,
		newLayout           = new_layout,
		srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		image               = image,
		subresourceRange = vk.ImageSubresourceRange {
			aspectMask     = {.COLOR},
			baseMipLevel   = 0,
			levelCount     = 1,
			baseArrayLayer = 0,
			layerCount     = 1,
		},
	}
	vk.CmdPipelineBarrier(cb, {.HOST}, {.FRAGMENT_SHADER}, {}, 0, nil, 0, nil, 1, &barrier)

	vk.EndCommandBuffer(cb)
	submit := vk.SubmitInfo {
		sType              = .SUBMIT_INFO,
		commandBufferCount = 1,
		pCommandBuffers    = &cb,
	}
	vk.QueueSubmit(r.queue, 1, &submit, 0)
	vk.DeviceWaitIdle(r.device)
	vk.FreeCommandBuffers(r.device, r.command_pool, 1, &cb)
}

place_bitmap :: proc (font: ^Font, pixels: [^]byte, w, h: int) -> (Glyph, bool) {
	if w <= 0 || h <= 0 {
		return Glyph {}, true
	}
	if font.cursor_x + w + 2*GLYPH_PAD > font.atlas_w {
		font.cursor_x = 0
		font.cursor_y += font.row_height
		font.row_height = 0
	}
	if font.cursor_y + h + 2*GLYPH_PAD > font.atlas_h {
		return font.fallback, false
	}

	px := font.cursor_x + GLYPH_PAD
	py := font.cursor_y + GLYPH_PAD
	mapped := cast([^]u8) font.mapped
	for row in 0 ..< h {
		for col in 0 ..< w {
			mapped[(py+row)*font.row_pitch + px + col] = pixels[row*w+col]
		}
	}

	g := Glyph {
		u0       = f32(px) / f32(font.atlas_w),
		v0       = f32(py) / f32(font.atlas_h),
		u1       = f32(px + w) / f32(font.atlas_w),
		v1       = f32(py + h) / f32(font.atlas_h),
		width    = f32(w),
		height   = f32(h),
		x_offset = 0,
		y_offset = 0,
		advance  = f32(w),
	}

	font.cursor_x += w + 2*GLYPH_PAD
	if h + 2*GLYPH_PAD > font.row_height {
		font.row_height = h + 2*GLYPH_PAD
	}
	return g, true
}

font_init :: proc (font: ^Font, r: ^Context, path: string, pixel_height: f32) -> bool {
	data, err := os.read_entire_file(path, context.allocator)
	if err != nil {
		return false
	}
	font.font_data = data

	offset := stbtt.GetFontOffsetForIndex(raw_data(data), 0)
	if offset < 0 {
		offset = 0
	}
	if !stbtt.InitFont(&font.info, raw_data(data), offset) {
		return false
	}

	ascent, descent, line_gap: c.int
	stbtt.GetFontVMetrics(&font.info, &ascent, &descent, &line_gap)
	font.scale = stbtt.ScaleForPixelHeight(&font.info, pixel_height)
	font.pixel_height = pixel_height
	font.size = font.scale * f32(ascent - descent)
	font.ascent = font.scale * f32(ascent)
	font.descent = font.scale * f32(descent)
	font.atlas_w = ATLAS_SIZE
	font.atlas_h = ATLAS_SIZE
	font.cursor_x = 0
	font.cursor_y = 0
	font.row_height = 0

	image_ci := vk.ImageCreateInfo {
		sType     = .IMAGE_CREATE_INFO,
		imageType = .D2,
		format    = .R8_UNORM,
		extent = vk.Extent3D {
			width  = u32(ATLAS_SIZE),
			height = u32(ATLAS_SIZE),
			depth  = 1,
		},
		mipLevels     = 1,
		arrayLayers   = 1,
		samples       = {._1},
		tiling        = .LINEAR,
		usage         = {.SAMPLED, .TRANSFER_DST},
		sharingMode   = .EXCLUSIVE,
		initialLayout = .PREINITIALIZED,
	}
	if vk.CreateImage(r.device, &image_ci, nil, &font.atlas_image) != .SUCCESS {
		return false
	}

	req: vk.MemoryRequirements
	vk.GetImageMemoryRequirements(r.device, font.atlas_image, &req)
	props: vk.PhysicalDeviceMemoryProperties
	vk.GetPhysicalDeviceMemoryProperties(r.physical_device, &props)
	mem_type := find_memory_type(props, req.memoryTypeBits, {.HOST_VISIBLE, .HOST_COHERENT})

	alloc := vk.MemoryAllocateInfo {
		sType           = .MEMORY_ALLOCATE_INFO,
		allocationSize  = req.size,
		memoryTypeIndex = mem_type,
	}
	if vk.AllocateMemory(r.device, &alloc, nil, &font.atlas_memory) != .SUCCESS {
		return false
	}
	vk.BindImageMemory(r.device, font.atlas_image, font.atlas_memory, 0)
	if vk.MapMemory(r.device, font.atlas_memory, 0, req.size, {}, &font.mapped) != .SUCCESS {
		return false
	}

	subresource := vk.ImageSubresource {aspectMask = {.COLOR}, mipLevel = 0, arrayLayer = 0}
	layout: vk.SubresourceLayout
	vk.GetImageSubresourceLayout(r.device, font.atlas_image, &subresource, &layout)
	font.row_pitch = int(layout.rowPitch)

	view_ci := vk.ImageViewCreateInfo {
		sType    = .IMAGE_VIEW_CREATE_INFO,
		image    = font.atlas_image,
		viewType = .D2,
		format   = .R8_UNORM,
		subresourceRange = vk.ImageSubresourceRange {
			aspectMask     = {.COLOR},
			baseMipLevel   = 0,
			levelCount     = 1,
			baseArrayLayer = 0,
			layerCount     = 1,
		},
	}
	if vk.CreateImageView(r.device, &view_ci, nil, &font.atlas_view) != .SUCCESS {
		return false
	}

	sampler_ci := vk.SamplerCreateInfo {
		sType                   = .SAMPLER_CREATE_INFO,
		magFilter               = .LINEAR,
		minFilter               = .LINEAR,
		mipmapMode              = .NEAREST,
		addressModeU            = .CLAMP_TO_EDGE,
		addressModeV            = .CLAMP_TO_EDGE,
		addressModeW            = .CLAMP_TO_EDGE,
		mipLodBias              = 0,
		anisotropyEnable        = false,
		maxAnisotropy           = 1,
		compareEnable           = false,
		compareOp               = .ALWAYS,
		minLod                  = 0,
		maxLod                  = 0,
		borderColor             = .FLOAT_OPAQUE_BLACK,
		unnormalizedCoordinates = false,
	}
	if vk.CreateSampler(r.device, &sampler_ci, nil, &font.sampler) != .SUCCESS {
		return false
	}

	// bake guaranteed white texel
	white := [1]byte {255}
	if g, placed := place_bitmap(font, &white[0], 1, 1); placed {
		font.white_uv = [2]f32 {(g.u0 + g.u1) / 2, (g.v0 + g.v1) / 2}
	}

	// bake a box glyph: fallback for missing glyphs
	box_size := int(pixel_height)
	if box_size < 2 {
		box_size = 2
	}
	box := make([]byte, box_size*box_size, context.temp_allocator)
	for i in 0 ..< box_size {
		for j in 0 ..< box_size {
			if i == 0 || i == box_size-1 || j == 0 || j == box_size-1 {
				box[i*box_size+j] = 255
			}
		}
	}
	if fallback, placed := place_bitmap(font, raw_data(box), box_size, box_size); placed {
		font.fallback = fallback
	}

	transition_image_layout(r, font.atlas_image, .PREINITIALIZED, .GENERAL)

	image_info := vk.DescriptorImageInfo {
		sampler     = font.sampler,
		imageView   = font.atlas_view,
		imageLayout = .GENERAL,
	}
	write := vk.WriteDescriptorSet {
		sType           = .WRITE_DESCRIPTOR_SET,
		dstSet          = r.descriptor_set,
		dstBinding      = 0,
		dstArrayElement = 0,
		descriptorCount = 1,
		descriptorType  = .COMBINED_IMAGE_SAMPLER,
		pImageInfo      = &image_info,
	}
	vk.UpdateDescriptorSets(r.device, 1, &write, 0, nil)

	font.valid = true
	return true
}

font_glyph :: proc (font: ^Font, r: rune) -> Glyph {
	if g, ok := font.glyphs[r]; ok {
		return g
	}
	if !font.valid {
		return font.fallback
	}

	advance_width, lsb: c.int
	stbtt.GetCodepointHMetrics(&font.info, r, &advance_width, &lsb)

	w, h, xoff, yoff: c.int
	bitmap := stbtt.GetCodepointBitmap(
		&font.info, font.scale, font.scale, r, &w, &h, &xoff, &yoff)

	g: Glyph
	if bitmap != nil && w > 0 && h > 0 {
		placed, ok := place_bitmap(font, bitmap, int(w), int(h))
		stbtt.FreeBitmap(bitmap, nil)
		if ok {
			placed.x_offset = f32(xoff)
			placed.y_offset = f32(yoff)
			placed.advance = f32(advance_width) * font.scale
			g = placed
		} else {
			g = font.fallback
		}
	} else {
		g = Glyph {advance = f32(advance_width) * font.scale}
	}

	font.glyphs[r] = g
	return g
}

font_measure :: proc (font: ^Font, text: string, scale: f32) -> [2]f32 {
	width: f32
	for r in text {
		width += font_glyph(font, r).advance * scale
	}
	return [2]f32 {width, font.size * scale}
}

font_destroy :: proc (font: ^Font, r: ^Context) {
	if font.sampler != 0 {
		vk.DestroySampler(r.device, font.sampler, nil)
		font.sampler = 0
	}
	if font.atlas_view != 0 {
		vk.DestroyImageView(r.device, font.atlas_view, nil)
		font.atlas_view = 0
	}
	if font.mapped != nil {
		vk.UnmapMemory(r.device, font.atlas_memory)
		font.mapped = nil
	}
	if font.atlas_memory != 0 {
		vk.FreeMemory(r.device, font.atlas_memory, nil)
		font.atlas_memory = 0
	}
	if font.atlas_image != 0 {
		vk.DestroyImage(r.device, font.atlas_image, nil)
		font.atlas_image = 0
	}
	if font.glyphs != nil {
		delete(font.glyphs)
		font.glyphs = nil
	}
	if font.font_data != nil {
		delete(font.font_data)
		font.font_data = nil
	}
	font.valid = false
}
