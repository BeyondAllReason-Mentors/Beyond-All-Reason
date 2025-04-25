#version 420
#extension GL_ARB_uniform_buffer_object : require
#extension GL_ARB_shader_storage_buffer_object : require
#extension GL_ARB_shading_language_420pack: require

//(c) Beherith (mysterme@gmail.com)

#line 5000

layout (location = 0) in vec4 vertexData;
layout (location = 1) in vec4 worldposrad; // -- target world pos and radius
layout (location = 2) in vec4 otherparams; // -- startframe, endframe, count, direction
layout (location = 3) in uint pieceIndex;
layout (location = 4) in uvec4 instData;

//__ENGINEUNIFORMBUFFERDEFS__
//__DEFINES__

struct SUniformsBuffer {
    uint composite; //     u8 drawFlag; u8 unused1; u16 id;
    
    uint unused2;
    uint unused3;
    uint unused4;

    float maxHealth;
    float health;
    float unused5;
    float unused6;
    
    vec4 drawPos;
    vec4 speed;
    vec4[4] userDefined; //can't use float[16] because float in arrays occupies 4 * float space
};

layout(std140, binding=1) readonly buffer UniformsBuffer {
    SUniformsBuffer uni[];
}; 

#define UNITID (uni[instData.y].composite >> 16)

#line 10000

uniform float addRadius = 0.0;
uniform float iconDistance = 20000.0;

out DataVS {
	uint v_numvertices;
	float v_rotationY;
	vec4 v_color;
	vec4 v_lengthwidthcornerheight;
	vec4 v_centerpos;
	vec4 v_parameters;
};

layout(std140, binding=0) readonly buffer MatrixBuffer {
	mat4 mat[];
};

bool vertexClipped(vec4 clipspace, float tolerance) {
  return any(lessThan(clipspace.xyz, -clipspace.www * tolerance)) ||
         any(greaterThan(clipspace.xyz, clipspace.www * tolerance));
}


#define GROWTHRATE 1.0
#define INITIALSIZE 1.0
#define BREATHERATE 1.0
#define BREATHESIZE 0.1
#define CLIPTOLERANCE 1.1
#define TRAVELTIME 80.0
#define SPEEDPOWER 0.6
#define PARTICLESIZE 12.0
#define DEFAULTCENTER vec3(0,32,0);

// These control the speed and amount of XYZ wobble, and the Alpha wobble 
#define FREQUENCIES vec4(10.0, 2.0, 3.0, 0.1)
#define AMPLITUDES vec4(0.5, 0.5, 0.5, 10)

void main()
{
	uint baseIndex = instData.x; // this tells us which unit matrix to find
	mat4 worldMatrix = mat[instData.x];
	if (pieceIndex > 0u) {
		mat4 pieceMatrix = mat[instData.x + pieceIndex];
		worldMatrix = worldMatrix * pieceMatrix;
	}
	
	v_numvertices = 4;
	vec4 piecePos = worldMatrix * vec4(0,0,0,1);
	
	if ((uni[instData.y].composite & 0x00000003u) < 1u ) {
		//v_numvertices = 0u; 
		// this checks the drawFlag of wether the unit is actually being drawn 
		// (this is ==1 when then unit is both visible and drawn as a full model (not icon)) 
		// in this case, fall  back to drawPos
		piecePos.xyz = uni[instData.y].drawPos.xyz + DEFAULTCENTER;
	};
	
	float dieframe = otherparams.y;
	if ((dieframe > 0)){
		piecePos.xyz = uni[instData.y].drawPos.xyz + DEFAULTCENTER;
		}
	
	float time = (timeInfo.x + timeInfo.w);
	
	float randSeeded = fract(UNITID / 32768.0 + vertexData.w);
	
	float deltaTime = fract(time /TRAVELTIME + randSeeded);
	
	if ((time/TRAVELTIME) < (otherparams.x /TRAVELTIME + deltaTime)){
		v_numvertices = 0;
	}
	// Only show ones after the time?

	// Calculate the position of particles, and take into account their directoin!
	float distanceToTarget = length(piecePos.xyz- worldposrad.xyz);
	float direction = otherparams.w; // 1 forward, -1 reverse, 0 bidirectoinal
	float positionModifier = deltaTime;
	if (direction > 0.5 ){// forward
		positionModifier = pow(deltaTime, SPEEDPOWER);
	}else if (direction < -0.5) { //reverse
		positionModifier = 1.0 - pow(deltaTime, SPEEDPOWER);
	}else {
		if (vertexData.y > 0.5) { // half reverse
			positionModifier = 1.0 - pow(deltaTime, SPEEDPOWER);
		}else{
			positionModifier = pow(deltaTime, SPEEDPOWER);
		}
	
	}
	
	// Finalize the position of the particle
	piecePos.xyz = mix(piecePos.xyz + (vertexData.xyz -0.5) * 2, worldposrad.xyz + (vertexData.xyz -0.5) * (worldposrad.w*1.3+1), positionModifier);

	// Calculate some sinuosoid patterns for movement
	float pidt = deltaTime * 3.1425 * 2;
	float sindt = sin(deltaTime * 3.1425);
	vec3 randopos = worldposrad.w* (-vertexData.xyz +0.5);
	
	vec4 frequencies = FREQUENCIES;
	vec4 offsets = vec4(vertexData.xzyy);
	vec4 amplitudes = AMPLITUDES;
	
	vec4 sintimes = sin(pidt * (frequencies + 6.28*offsets));
	
	// Offset the positions of the particles with the sinusoid factor
	piecePos.xyz = mix(piecePos.xyz, piecePos.xyz + (sintimes.xyz * amplitudes.xyz), sindt);
	
	//Set the size of the particles
	vec4 lengthwidthcornerheight = vec4(PARTICLESIZE,PARTICLESIZE,16,16);

	// Transform into world space
	gl_Position = cameraViewProj * piecePos; // We transform this vertex into the center of the model
	
	v_parameters = otherparams;
	
	// Calculate the color of the particle
	uint teamIndex = (instData.z & 0x000000FFu); //leftmost ubyte is teamIndex
	v_color = teamColor[teamIndex];  // We can lookup the teamcolor right here
	v_color.a *= (1.0 + amplitudes.w * sintimes.w);
	//v_color.a = clamp(v_color.a, 0, 1);
	
	// Pass the center position to the geometry shader TODO: use gl_Position instead, to save some varyings
	v_centerpos = vec4( piecePos.xyz, 1.0); // We are going to pass the centerpoint to the GS
	
	// Pass through all other parameters.
	v_lengthwidthcornerheight = lengthwidthcornerheight;
	v_parameters.zw = vertexData.yz; // some useful randoms 
	

	// Modulate the size of the particle from spawn time and from its age
	float ageAnimation = clamp(((timeInfo.x + timeInfo.w) - otherparams.x)/GROWTHRATE + INITIALSIZE, INITIALSIZE, 1.0);
	float sizeAnimation =  sin((timeInfo.x)/BREATHERATE)*BREATHESIZE;
	v_lengthwidthcornerheight.xy *= (ageAnimation+sizeAnimation); // modulate it with animation factor

	//Fade out when stopped
	if ((dieframe > 0)){
		float fadeout = clamp( (dieframe +FADEOUT - time )/FADEOUT ,0,1);
		v_color.a *= fadeout * fadeout;
		//v_color += 1.0;
		//v_color.rgba = vec4(1,0,1,v_color.a * fadeout * fadeout);
		
		// Done keep emitting
		if (deltaTime < (1.0 - fadeout)) v_color -= 2.0;
	}

	if (vertexClipped(gl_Position, CLIPTOLERANCE)) v_numvertices = 0; // Make no primitives on stuff outside of screen
	// TODO: take into account size of primitive before clipping

	// this sets the num prims to 0 for units further from cam than iconDistance
	//float cameraDistance = length((cameraViewInv[3]).xyz - v_centerpos.xyz);
	//if (cameraDistance > iconDistance) v_numvertices = 0;

	// if the center pos is at (0,0,0) then we probably dont have the matrix yet for this unit, because it entered LOS but has not been drawn yet.
	//if (dot(v_centerpos.xyz, v_centerpos.xyz) < 1.0) v_numvertices = 0; 

	// TODO: allow overriding this check, to draw things even if unit (like a building) is not drawn, by using the piecepos info
	
}
