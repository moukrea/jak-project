#version 410 core
layout (location = 0) in vec3 position_in;
uniform vec4 cam_trans;
uniform mat4 u_smvp;
void main() {
  gl_Position = u_smvp * vec4((position_in - cam_trans.xyz) * (1.0 / 4096.0), 1.0);
}
