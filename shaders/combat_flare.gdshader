shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled;
uniform vec4 tint : source_color = vec4(0.2,0.8,1.0,1.0);
uniform float shape = 0.0;
instance uniform float phase = 0.0;
void fragment(){
    vec2 p=(UV-0.5)*2.0;
    float r=length(p);
    float core=exp(-r*r*22.0);
    float rays=pow(abs(cos(atan(p.y,p.x)*4.0)),16.0)*pow(max(0.0,1.0-r),2.5);
    float ring=exp(-pow((r-(0.14+phase*0.68))*21.0,2.0));
    float value=mix(core+rays*0.65,ring,shape);
    ALBEDO=tint.rgb;
    EMISSION=tint.rgb*3.5+vec3(core*0.8*(1.0-shape));
    ALPHA=min(0.9,value*(1.0-phase)*tint.a);
}
