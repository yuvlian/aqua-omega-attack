#version 450
layout(push_constant) uniform Push { vec2 viewport; vec4 outline_color; } pc;
layout(set = 0, binding = 0) uniform sampler2D tex;
layout(location = 0) in vec2 frag_uv;
layout(location = 1) in vec4 frag_color;
layout(location = 2) in vec2 frag_shape;
layout(location = 0) out vec4 out_color;

void main() {
    float mode = frag_shape.x;
    float thickness = frag_shape.y;

    if (mode > 1.5) {
        float d = length(frag_uv - 0.5);
        float px_per_uv = 1.0 / max(fwidth(frag_uv.x), 1e-6);
        float d_px = d * px_per_uv;
        float radius_px = 0.5 * px_per_uv;
        float a;
        if (mode > 2.5) {
            float ring_px = abs(d_px - radius_px);
            a = frag_color.a * (1.0 - smoothstep(thickness - 0.5, thickness + 0.5, ring_px));
        } else {
            a = frag_color.a * (1.0 - smoothstep(radius_px - 0.5, radius_px + 0.5, d_px));
        }
        out_color = vec4(frag_color.rgb * a, a);
        return;
    }

    if (mode > 0.5) {
        vec2 f = fwidth(frag_uv);
        float dx = min(frag_uv.x, 1.0 - frag_uv.x) / max(f.x, 1e-6);
        float dy = min(frag_uv.y, 1.0 - frag_uv.y) / max(f.y, 1e-6);
        float d = min(dx, dy);
        float a = frag_color.a * (1.0 - smoothstep(thickness - 0.5, thickness + 0.5, d));
        out_color = vec4(frag_color.rgb * a, a);
        return;
    }

    float t = 1.0 / 1024.0;
    float inner = texture(tex, frag_uv).r;
    float up    = texture(tex, frag_uv + vec2(0.0, t)).r;
    float down  = texture(tex, frag_uv + vec2(0.0, -t)).r;
    float left  = texture(tex, frag_uv + vec2(-t, 0.0)).r;
    float right = texture(tex, frag_uv + vec2(t, 0.0)).r;
    float edge  = max(max(inner, up), max(max(down, left), right));

    float is_outline = edge - inner;
    float is_text    = inner;

    vec3 premul = frag_color.rgb * frag_color.a * is_text
                + pc.outline_color.rgb * pc.outline_color.a * is_outline;
    float a = frag_color.a * is_text + pc.outline_color.a * is_outline;
    out_color = vec4(premul, a);
}
