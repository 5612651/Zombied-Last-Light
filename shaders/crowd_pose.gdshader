shader_type spatial;

uniform vec4 base_color : source_color = vec4(1.0);
uniform float metalness = 0.0;
uniform float surface_roughness = 0.65;
uniform vec3 glow_color : source_color = vec3(0.0);
uniform float glow_energy = 0.0;
instance uniform float walk_phase = 0.0;
instance uniform float hit_flash = 0.0;

void vertex() {
    // COLOR.r tags left/right leg and boot vertices in the batched pose.
    if (COLOR.r > 0.25) {
        float side = COLOR.r < 0.75 ? -1.0 : 1.0;
        float angle = -side * sin(walk_phase) * 0.45;
        float c = cos(angle);
        float s = sin(angle);
        vec3 offset = VERTEX - vec3(side * 0.18, 0.38, 0.0);
        VERTEX.y = 0.38 + offset.y * c - offset.z * s;
        VERTEX.z = offset.y * s + offset.z * c;
        NORMAL.yz = vec2(NORMAL.y * c - NORMAL.z * s, NORMAL.y * s + NORMAL.z * c);
    }
}

void fragment() {
    ALBEDO = mix(base_color.rgb, vec3(0.957, 0.890, 0.737), hit_flash);
    METALLIC = metalness;
    ROUGHNESS = surface_roughness;
    EMISSION = glow_color * glow_energy + vec3(1.9, 1.7, 1.3) * hit_flash;
}
