#version 450
layout(push_constant) uniform Push { vec2 viewport; vec4 outline_color; } pc;
layout(location = 0) in vec2 in_pos;
layout(location = 1) in vec2 in_uv;
layout(location = 2) in vec4 in_color;
layout(location = 3) in vec2 in_shape;
layout(location = 0) out vec2 frag_uv;
layout(location = 1) out vec4 frag_color;
layout(location = 2) out vec2 frag_shape;
void main() {
    frag_uv = in_uv;
    frag_color = in_color;
    frag_shape = in_shape;
    vec2 ndc = vec2(in_pos.x / pc.viewport.x * 2.0 - 1.0, in_pos.y / pc.viewport.y * 2.0 - 1.0);
    gl_Position = vec4(ndc, 0.0, 1.0);
}
