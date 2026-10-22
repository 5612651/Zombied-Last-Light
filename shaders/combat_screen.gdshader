shader_type canvas_item;
uniform sampler2D scene_texture : hint_screen_texture, filter_linear;
uniform float strength = 1.0;
uniform float blood = 0.0;
uniform float low_health = 0.0;
uniform float dust = 0.0;
uniform float poison = 0.0;
uniform float heat = 0.0;
uniform float shock_progress = 1.0;
uniform float shock_active = 0.0;
uniform float boss_impact = 0.0;
uniform vec2 shock_origin = vec2(0.5);
uniform float aspect = 1.6;

float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
void fragment() {
    vec2 uv=SCREEN_UV;
    vec2 radial=(uv-shock_origin)*vec2(aspect,1.0);
    float distance_from_blast=length(radial);
    float wave=exp(-pow((distance_from_blast-shock_progress*0.95)*35.0,2.0));
    uv+=normalize(radial+vec2(0.0001))*wave*(1.0-shock_progress)*0.012*shock_active*strength;
    uv.x+=sin(uv.y*55.0+TIME*6.0)*heat*0.0025*strength;
    uv.y+=sin(uv.x*42.0-TIME*4.0)*heat*0.0015*strength;
    vec3 scene=texture(scene_texture,clamp(uv,vec2(0.001),vec2(0.999))).rgb;
    vec2 centered=(SCREEN_UV-0.5)*2.0;
    float edge=smoothstep(0.45,1.15,length(centered));
    float speck=hash(floor(SCREEN_UV*vec2(73.0,49.0)));
    float stain=smoothstep(0.67,0.95,speck)*edge;
    scene=mix(scene,vec3(0.24,0.018,0.015),blood*(edge*0.12+stain*0.38)*strength);
    float heartbeat=0.5+0.5*sin(TIME*7.0);
    scene*=1.0-edge*low_health*(0.22+heartbeat*0.1)*strength;
    scene=mix(scene,scene*vec3(0.8,1.12,0.73),poison*(0.12+edge*0.3)*strength);
    scene=mix(scene,vec3(0.42,0.33,0.22),dust*(0.06+speck*0.12)*strength);
    scene=mix(scene,vec3(0.65,0.18,0.045),heat*edge*0.12*strength);
    scene*=1.0-edge*boss_impact*0.22*strength;
    COLOR=vec4(scene,1.0);
}
