-- Numeric transforms; avoids a reflected Unreal call per body per render frame.
local M={}
local deg=180/math.pi
function M.rotator(t)
 local x,y,z,w=t[4],t[5],t[6],t[7]
 local s=z*x-w*y
 local yaw=math.atan(2*(w*z+x*y),1-2*(y*y+z*z))*deg
 local pitch,roll
 if s<-.4999995 then pitch=-90;roll=-yaw-2*math.atan(x,w)*deg
 elseif s>.4999995 then pitch=90;roll=yaw-2*math.atan(x,w)*deg
 else pitch=math.asin(math.max(-1,math.min(1,2*s)))*deg
  roll=math.atan(-2*(w*x+y*z),1-2*(x*x+y*y))*deg
 end
 return {Pitch=pitch,Yaw=yaw,Roll=(roll+180)%360-180}
end
function M.rotate(q,v,inverse)
 local sign=inverse and -1 or 1
 local x,y,z,w=q[4]*sign,q[5]*sign,q[6]*sign,q[7]
 local tx,ty,tz=2*(y*v[3]-z*v[2]),2*(z*v[1]-x*v[3]),2*(x*v[2]-y*v[1])
 return {v[1]+w*tx+y*tz-z*ty,v[2]+w*ty+z*tx-x*tz,v[3]+w*tz+x*ty-y*tx}
end
function M.point(v,from,to)
 local p=M.rotate(from,{v[1]-from[1],v[2]-from[2],v[3]-from[3]},true)
 p=M.rotate(to,p)
 return {p[1]+to[1],p[2]+to[2],p[3]+to[3]}
end
function M.transform(t,from,to)
 local p=M.point(t,from,to)
 local function mul(a,b)return {a[4]*b[1]+a[1]*b[4]+a[2]*b[3]-a[3]*b[2],
  a[4]*b[2]-a[1]*b[3]+a[2]*b[4]+a[3]*b[1],
  a[4]*b[3]+a[1]*b[2]-a[2]*b[1]+a[3]*b[4],
  a[4]*b[4]-a[1]*b[1]-a[2]*b[2]-a[3]*b[3]}end
 local q=mul({to[4],to[5],to[6],to[7]},mul({-from[4],-from[5],-from[6],from[7]},
  {t[4],t[5],t[6],t[7]}))
 return {p[1],p[2],p[3],q[1],q[2],q[3],q[4],t[8],t[9],t[10]}
end
return M
