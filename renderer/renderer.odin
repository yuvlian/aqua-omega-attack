package renderer

import "core:sys/windows"
import vk "vendor:vulkan"
import "../cfg"

Push_Constant :: struct #packed {
	viewport:      [2]f32,
	_padding:      [2]f32,
	outline_color: [4]f32,
}

text_outline: [4]f32 = {0, 0, 0, 1}

renderer_set_text_outline :: proc (r, g, b, a: u8) {
	text_outline = [4]f32 {f32(r)/255, f32(g)/255, f32(b)/255, f32(a)/255}
}

Context :: struct {
	instance:              vk.Instance,
	physical_device:       vk.PhysicalDevice,
	device:                vk.Device,
	queue:                 vk.Queue,
	queue_family:          u32,
	extent:                vk.Extent2D,
	color_image:           vk.Image,
	color_view:            vk.ImageView,
	color_memory:          vk.DeviceMemory,
	color_framebuffer:     vk.Framebuffer,
	staging_buffer:        vk.Buffer,
	staging_memory:        vk.DeviceMemory,
	staging_size:          vk.DeviceSize,
	staging_mapped:        rawptr,
	render_pass:           vk.RenderPass,
	command_pool:          vk.CommandPool,
	command_buffer:        vk.CommandBuffer,
	fence:                 vk.Fence,
	vk_lib:                windows.HMODULE,
	pipeline:              vk.Pipeline,
	pipeline_layout:       vk.PipelineLayout,
	descriptor_set_layout: vk.DescriptorSetLayout,
	descriptor_pool:       vk.DescriptorPool,
	descriptor_set:        vk.DescriptorSet,
	vertex_buffer:         vk.Buffer,
	index_buffer:          vk.Buffer,
	vertex_buffer_memory:  vk.DeviceMemory,
	index_buffer_memory:   vk.DeviceMemory,
	vertex_count:          u32,
	index_count:           u32,
}

ctx: Context


pick_physical_device :: proc (r: ^Context) -> (vk.PhysicalDevice, u32, bool) {
	count: u32
	vk.EnumeratePhysicalDevices(r.instance, &count, nil)
	if count == 0 {
		return nil, 0, false
	}
	devices := make([]vk.PhysicalDevice, int(count), context.temp_allocator)
	vk.EnumeratePhysicalDevices(r.instance, &count, raw_data(devices))

	fallback: vk.PhysicalDevice
	fallback_family: u32
	fallback_ok := false

	for dev in devices {
		family_count: u32
		vk.GetPhysicalDeviceQueueFamilyProperties(dev, &family_count, nil)
		families := make([]vk.QueueFamilyProperties, int(family_count), context.temp_allocator)
		vk.GetPhysicalDeviceQueueFamilyProperties(dev, &family_count, raw_data(families))

		family: u32
		family_found := false
		for i in 0 ..< int(family_count) {
			if .GRAPHICS in families[i].queueFlags {
				family = u32(i)
				family_found = true
				break
			}
		}

		if !family_found {
			continue
		}

		props: vk.PhysicalDeviceProperties
		vk.GetPhysicalDeviceProperties(dev, &props)

		if !fallback_ok {
			fallback = dev
			fallback_family = family
			fallback_ok = true
		}

		if props.deviceType == .DISCRETE_GPU {
			return dev, family, true
		}
	}

	if fallback_ok {
		return fallback, fallback_family, true
	}
	return nil, 0, false
}

create_render_pass :: proc (r: ^Context) -> bool {
	color_attachment := vk.AttachmentDescription {
		format         = .B8G8R8A8_UNORM,
		samples        = {._1},
		loadOp         = .CLEAR,
		storeOp        = .STORE,
		stencilLoadOp  = .DONT_CARE,
		stencilStoreOp = .DONT_CARE,
		initialLayout  = .UNDEFINED,
		finalLayout    = .TRANSFER_SRC_OPTIMAL,
	}

	color_ref := vk.AttachmentReference {attachment = 0, layout = .COLOR_ATTACHMENT_OPTIMAL}
	subpass := vk.SubpassDescription {
		pipelineBindPoint    = .GRAPHICS,
		colorAttachmentCount = 1,
		pColorAttachments    = &color_ref,
	}

	render_pass_ci := vk.RenderPassCreateInfo {
		sType           = .RENDER_PASS_CREATE_INFO,
		attachmentCount = 1,
		pAttachments    = &color_attachment,
		subpassCount    = 1,
		pSubpasses      = &subpass,
	}

	return vk.CreateRenderPass(r.device, &render_pass_ci, nil, &r.render_pass) == .SUCCESS
}

create_offscreen :: proc (r: ^Context, width, height: int) -> bool {
	r.extent = vk.Extent2D {width = u32(width), height = u32(height)}

	image_ci := vk.ImageCreateInfo {
		sType         = .IMAGE_CREATE_INFO,
		imageType     = .D2,
		format        = .B8G8R8A8_UNORM,
		extent        = vk.Extent3D {width = r.extent.width, height = r.extent.height, depth = 1},
		mipLevels     = 1,
		arrayLayers   = 1,
		samples       = {._1},
		tiling        = .OPTIMAL,
		usage         = {.COLOR_ATTACHMENT, .TRANSFER_SRC},
		sharingMode   = .EXCLUSIVE,
		initialLayout = .UNDEFINED,
	}
	if vk.CreateImage(r.device, &image_ci, nil, &r.color_image) != .SUCCESS {
		return false
	}

	req: vk.MemoryRequirements
	vk.GetImageMemoryRequirements(r.device, r.color_image, &req)
	props: vk.PhysicalDeviceMemoryProperties
	vk.GetPhysicalDeviceMemoryProperties(r.physical_device, &props)
	mem_type := find_memory_type(props, req.memoryTypeBits, {.DEVICE_LOCAL})

	alloc := vk.MemoryAllocateInfo {
		sType           = .MEMORY_ALLOCATE_INFO,
		allocationSize  = req.size,
		memoryTypeIndex = mem_type,
	}
	if vk.AllocateMemory(r.device, &alloc, nil, &r.color_memory) != .SUCCESS {
		return false
	}
	vk.BindImageMemory(r.device, r.color_image, r.color_memory, 0)

	view_ci := vk.ImageViewCreateInfo {
		sType    = .IMAGE_VIEW_CREATE_INFO,
		image    = r.color_image,
		viewType = .D2,
		format   = .B8G8R8A8_UNORM,
		subresourceRange = vk.ImageSubresourceRange {
			aspectMask     = {.COLOR},
			baseMipLevel   = 0,
			levelCount     = 1,
			baseArrayLayer = 0,
			layerCount     = 1,
		},
	}
	if vk.CreateImageView(r.device, &view_ci, nil, &r.color_view) != .SUCCESS {
		return false
	}

	fb_ci := vk.FramebufferCreateInfo {
		sType           = .FRAMEBUFFER_CREATE_INFO,
		renderPass      = r.render_pass,
		attachmentCount = 1,
		pAttachments    = &r.color_view,
		width           = r.extent.width,
		height          = r.extent.height,
		layers          = 1,
	}
	if vk.CreateFramebuffer(r.device, &fb_ci, nil, &r.color_framebuffer) != .SUCCESS {
		return false
	}

	r.staging_size = vk.DeviceSize(width * height * 4)
	buf_ci := vk.BufferCreateInfo {
		sType       = .BUFFER_CREATE_INFO,
		size        = r.staging_size,
		usage       = {.TRANSFER_DST},
		sharingMode = .EXCLUSIVE,
	}
	if vk.CreateBuffer(r.device, &buf_ci, nil, &r.staging_buffer) != .SUCCESS {
		return false
	}

	buf_req: vk.MemoryRequirements
	vk.GetBufferMemoryRequirements(r.device, r.staging_buffer, &buf_req)

	buf_mem_type := find_memory_type(
		props, buf_req.memoryTypeBits, {.HOST_VISIBLE, .HOST_CACHED})

	buf_alloc := vk.MemoryAllocateInfo {
		sType           = .MEMORY_ALLOCATE_INFO,
		allocationSize  = buf_req.size,
		memoryTypeIndex = buf_mem_type,
	}

	if vk.AllocateMemory(r.device, &buf_alloc, nil, &r.staging_memory) != .SUCCESS {
		return false
	}

	vk.BindBufferMemory(r.device, r.staging_buffer, r.staging_memory, 0)

	if vk.MapMemory(
		r.device,
		r.staging_memory,
		0,
		r.staging_size,
		{},
		&r.staging_mapped,
	) != .SUCCESS {
		return false
	}

	return true
}

destroy_offscreen :: proc (r: ^Context) {
	if r.staging_mapped != nil {
		vk.UnmapMemory(r.device, r.staging_memory)
		r.staging_mapped = nil
	}
	if r.staging_memory != 0 {
		vk.FreeMemory(r.device, r.staging_memory, nil)
		r.staging_memory = 0
	}
	if r.staging_buffer != 0 {
		vk.DestroyBuffer(r.device, r.staging_buffer, nil)
		r.staging_buffer = 0
	}
	if r.color_framebuffer != 0 {
		vk.DestroyFramebuffer(r.device, r.color_framebuffer, nil)
		r.color_framebuffer = 0
	}
	if r.color_view != 0 {
		vk.DestroyImageView(r.device, r.color_view, nil)
		r.color_view = 0
	}
	if r.color_memory != 0 {
		vk.FreeMemory(r.device, r.color_memory, nil)
		r.color_memory = 0
	}
	if r.color_image != 0 {
		vk.DestroyImage(r.device, r.color_image, nil)
		r.color_image = 0
	}
}

create_command_pool :: proc (r: ^Context) -> bool {
	pool_ci := vk.CommandPoolCreateInfo {
		sType            = .COMMAND_POOL_CREATE_INFO,
		flags            = {.RESET_COMMAND_BUFFER},
		queueFamilyIndex = r.queue_family,
	}
	if vk.CreateCommandPool(r.device, &pool_ci, nil, &r.command_pool) != .SUCCESS {
		return false
	}
	alloc_info := vk.CommandBufferAllocateInfo {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool        = r.command_pool,
		level              = .PRIMARY,
		commandBufferCount = 1,
	}
	return vk.AllocateCommandBuffers(r.device, &alloc_info, &r.command_buffer) == .SUCCESS
}

create_fence :: proc (r: ^Context) -> bool {
	fence_ci := vk.FenceCreateInfo {sType = .FENCE_CREATE_INFO, flags = {.SIGNALED}}
	return vk.CreateFence(r.device, &fence_ci, nil, &r.fence) == .SUCCESS
}

create_descriptors :: proc (r: ^Context) -> bool {
	binding := vk.DescriptorSetLayoutBinding {
		binding         = 0,
		descriptorType  = .COMBINED_IMAGE_SAMPLER,
		descriptorCount = 1,
		stageFlags      = {.FRAGMENT},
	}
	layout_ci := vk.DescriptorSetLayoutCreateInfo {
		sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
		bindingCount = 1,
		pBindings    = &binding,
	}
	if vk.CreateDescriptorSetLayout(
		r.device,
		&layout_ci,
		nil,
		&r.descriptor_set_layout,
	) != .SUCCESS {
		return false
	}

	pool_size := vk.DescriptorPoolSize {type = .COMBINED_IMAGE_SAMPLER, descriptorCount = 1}
	pool_ci := vk.DescriptorPoolCreateInfo {
		sType         = .DESCRIPTOR_POOL_CREATE_INFO,
		maxSets       = 1,
		poolSizeCount = 1,
		pPoolSizes    = &pool_size,
	}
	if vk.CreateDescriptorPool(r.device, &pool_ci, nil, &r.descriptor_pool) != .SUCCESS {
		return false
	}

	alloc_info := vk.DescriptorSetAllocateInfo {
		sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
		descriptorPool     = r.descriptor_pool,
		descriptorSetCount = 1,
		pSetLayouts        = &r.descriptor_set_layout,
	}
	return vk.AllocateDescriptorSets(r.device, &alloc_info, &r.descriptor_set) == .SUCCESS
}

renderer_init :: proc (r: ^Context, width, height: int) -> bool {
	r.vk_lib = windows.LoadLibraryW("vulkan-1.dll")
	if r.vk_lib == nil {
		return false
	}
	vk.load_proc_addresses_global(windows.GetProcAddress(r.vk_lib, "vkGetInstanceProcAddr"))

	app_info := vk.ApplicationInfo {
		sType              = .APPLICATION_INFO,
		pApplicationName   = cfg.APPLICATION_NAME,
		applicationVersion = 1,
		pEngineName        = cfg.ENGINE_NAME,
		apiVersion         = vk.API_VERSION_1_0,
	}
	instance_ci := vk.InstanceCreateInfo {
		sType            = .INSTANCE_CREATE_INFO,
		pApplicationInfo = &app_info,
	}
	if vk.CreateInstance(&instance_ci, nil, &r.instance) != .SUCCESS {
		return false
	}
	vk.load_proc_addresses_instance(r.instance)

	physical_device, family, ok := pick_physical_device(r)
	if !ok {
		return false
	}
	r.physical_device = physical_device
	r.queue_family = family

	priority := f32(1.0)
	dqi := vk.DeviceQueueCreateInfo {
		sType            = .DEVICE_QUEUE_CREATE_INFO,
		queueFamilyIndex = family,
		queueCount       = 1,
		pQueuePriorities = &priority,
	}
	device_ci := vk.DeviceCreateInfo {
		sType                = .DEVICE_CREATE_INFO,
		queueCreateInfoCount = 1,
		pQueueCreateInfos    = &dqi,
	}
	if vk.CreateDevice(r.physical_device, &device_ci, nil, &r.device) != .SUCCESS {
		return false
	}
	vk.GetDeviceQueue(r.device, family, 0, &r.queue)

	if !create_render_pass(r) {
		return false
	}
	if !create_offscreen(r, width, height) {
		return false
	}
	if !create_command_pool(r) {
		return false
	}
	if !create_fence(r) {
		return false
	}
	if !create_descriptors(r) {
		return false
	}
	if !draw_pipeline_create(r) {
		return false
	}
	if !draw_buffers_create(r) {
		return false
	}

	return true
}

renderer_begin_frame :: proc (r: ^Context) -> bool {
	if vk.WaitForFences(r.device, 1, &r.fence, true, max(u64)) != .SUCCESS {
		return false
	}
	vk.ResetFences(r.device, 1, &r.fence)

	begin := vk.CommandBufferBeginInfo {sType = .COMMAND_BUFFER_BEGIN_INFO}
	vk.BeginCommandBuffer(r.command_buffer, &begin)

	clear_color := vk.ClearValue {color = vk.ClearColorValue {float32 = [4]f32 {0, 0, 0, 0}}}
	render_area := vk.Rect2D {offset = vk.Offset2D {x = 0, y = 0}, extent = r.extent}
	rp_begin := vk.RenderPassBeginInfo {
		sType           = .RENDER_PASS_BEGIN_INFO,
		renderPass      = r.render_pass,
		framebuffer     = r.color_framebuffer,
		renderArea      = render_area,
		clearValueCount = 1,
		pClearValues    = &clear_color,
	}
	vk.CmdBeginRenderPass(r.command_buffer, &rp_begin, .INLINE)

	viewport := vk.Viewport {
		x        = 0,
		y        = 0,
		width    = f32(r.extent.width),
		height   = f32(r.extent.height),
		minDepth = 0,
		maxDepth = 1,
	}
	scissor := vk.Rect2D {offset = vk.Offset2D {x = 0, y = 0}, extent = r.extent}
	vk.CmdSetViewport(r.command_buffer, 0, 1, &viewport)
	vk.CmdSetScissor(r.command_buffer, 0, 1, &scissor)

	pc := Push_Constant {
		viewport      = [2]f32 {f32(r.extent.width), f32(r.extent.height)},
		outline_color = text_outline,
	}
	vk.CmdPushConstants(
		r.command_buffer,
		r.pipeline_layout,
		{.VERTEX, .FRAGMENT},
		0,
		u32(size_of(Push_Constant)),
		&pc,
	)

	draw_begin()
	return true
}

renderer_present :: proc (r: ^Context, hwnd: windows.HWND) -> bool {
	if vk.WaitForFences(r.device, 1, &r.fence, true, max(u64)) != .SUCCESS {
		return false
	}
	if r.staging_mapped == nil {
		return false
	}
	invalidate_range := vk.MappedMemoryRange {
		sType  = .MAPPED_MEMORY_RANGE,
		memory = r.staging_memory,
		offset = 0,
		size   = r.staging_size,
	}
	vk.InvalidateMappedMemoryRanges(r.device, 1, &invalidate_range)
	present_frame(hwnd, r.staging_mapped)
	return true
}

renderer_destroy :: proc (r: ^Context) {
	if r.device != nil {
		vk.DeviceWaitIdle(r.device)
		draw_buffers_destroy(r)
		draw_pipeline_destroy(r)
		font_destroy(&font, r)

		if r.descriptor_pool != 0 {
			vk.DestroyDescriptorPool(r.device, r.descriptor_pool, nil)
			r.descriptor_pool = 0
		}
		if r.descriptor_set_layout != 0 {
			vk.DestroyDescriptorSetLayout(r.device, r.descriptor_set_layout, nil)
			r.descriptor_set_layout = 0
		}
		if r.fence != 0 {
			vk.DestroyFence(r.device, r.fence, nil)
			r.fence = 0
		}
		if r.command_pool != 0 {
			vk.DestroyCommandPool(r.device, r.command_pool, nil)
			r.command_pool = 0
		}
		destroy_offscreen(r)
		if r.render_pass != 0 {
			vk.DestroyRenderPass(r.device, r.render_pass, nil)
			r.render_pass = 0
		}
		if r.device != nil {
			vk.DestroyDevice(r.device, nil)
			r.device = nil
		}
		if r.instance != nil {
			vk.DestroyInstance(r.instance, nil)
			r.instance = nil
		}
	}
	if r.vk_lib != nil {
		windows.FreeLibrary(r.vk_lib)
		r.vk_lib = nil
	}
}
