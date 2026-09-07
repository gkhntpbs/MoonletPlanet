#include <metal_stdlib>

using namespace metal;

typedef struct {
    float2 viewportSize;
    float time;
    uint archetype;
    uint seed;
    float rotationSpeed;
    float turbulence;
    float detail;
    float warpStrength;
    float bandCount;
    float bandSharpness;
    float stormCount;
    float stormStrength;
    float cloudCoverage;
    float cloudSpeed;
    float atmosphereDensity;
    float atmosphereGlow;
    float roughness;
    float featureAmount;
    float lightAzimuth;
    float lightElevation;
    float exposure;
    float ringOpacity;
    float axialTilt;
    float ringInnerRadius;
    float ringOuterRadius;
    float ringDetail;
    float iceCoverage;
    float iceAltitude;
    float polarAsymmetry;
    float microDetail;
    float rotationPhase;
    float dayNightSpeed;
    uint life;
    float4 color0;
    float4 color1;
    float4 color2;
    float4 color3;
    float4 atmosphereColor;
    float4 ringColor;
    float4 iceColor;
    float4 lifeColor;
} MoonletPlanetUniforms;

struct MoonletPlanetVertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex MoonletPlanetVertexOut moonletPlanetVertex(uint vertexID [[vertex_id]]) {
    constexpr float2 positions[] = {
        float2(-1, -1),
        float2(1, -1),
        float2(-1, 1),
        float2(1, 1)
    };
    MoonletPlanetVertexOut output;
    output.position = float4(positions[vertexID], 0, 1);
    output.uv = positions[vertexID] * 0.5 + 0.5;
    return output;
}

float moonletHash(float3 p, uint seed) {
    p = fract(p * 0.1031 + float(seed % 4093u) * 0.000244);
    p += dot(p, p.yzx + 33.33);
    return fract((p.x + p.y) * p.z);
}

float moonletNoise(float3 p, uint seed) {
    float3 i = floor(p);
    float3 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float n000 = moonletHash(i, seed);
    float n100 = moonletHash(i + float3(1, 0, 0), seed);
    float n010 = moonletHash(i + float3(0, 1, 0), seed);
    float n110 = moonletHash(i + float3(1, 1, 0), seed);
    float n001 = moonletHash(i + float3(0, 0, 1), seed);
    float n101 = moonletHash(i + float3(1, 0, 1), seed);
    float n011 = moonletHash(i + float3(0, 1, 1), seed);
    float n111 = moonletHash(i + float3(1, 1, 1), seed);
    float n00 = mix(n000, n100, f.x);
    float n10 = mix(n010, n110, f.x);
    float n01 = mix(n001, n101, f.x);
    float n11 = mix(n011, n111, f.x);
    return mix(mix(n00, n10, f.y), mix(n01, n11, f.y), f.z);
}

float moonletFBM(float3 p, uint seed, float detail) {
    float value = 0;
    float amplitude = 0.52;
    float frequency = 1;
    for (uint octave = 0; octave < 8; octave++) {
        value += moonletNoise(p * frequency, seed + octave * 97u) * amplitude;
        frequency *= 2.04;
        amplitude *= mix(0.42, 0.56, detail);
    }
    return value;
}

/// High-frequency detail, on its own rather than as more octaves of the main field.
///
/// The eye reads resolution off the *finest* thing in the image, and a self-similar sum
/// buries its finest octave under everything above it. Four octaves starting where the main
/// field stops give a surface something to be sharp about, and cost the same wherever they
/// are added rather than multiplying every FBM in the shader.
float moonletMicro(float3 p, uint seed) {
    float value = 0;
    float amplitude = 0.5;
    float frequency = 1;
    for (uint octave = 0; octave < 4; octave++) {
        value += moonletNoise(p * frequency, seed + octave * 211u) * amplitude;
        frequency *= 2.11;
        amplitude *= 0.52;
    }
    return value;
}

/// Where a world is cold enough to keep ice on the ground.
///
/// Not a circle drawn at a latitude. The annual mean sunlight a latitude receives is very
/// nearly S(φ) ∝ 1 − 0.482·P₂(sin φ), the second-Legendre approximation used in energy
/// balance models — about 1.24 at the equator falling to 0.52 at the pole. Ice sits wherever
/// that, minus what altitude takes away, falls under the freezing isotherm.
///
/// Three things fall out of doing it this way rather than by drawing a cap:
///   * caps have the right *shape* — wide and flat-edged, not spherical caps seen in
///     projection, because the isotherm is a curve in latitude and not a small circle;
///   * highland ice appears far from the poles, which is why Kilimanjaro has snow on the
///     equator, controlled by `iceAltitude` as a lapse rate;
///   * the two caps differ, because they do. `polarAsymmetry` stands in for the land
///     distribution and orbital eccentricity that make Antarctica bigger than the Arctic and
///     Mars's southern cap outlast its northern one.
float moonletPolarIce(float3 n, float elevation, constant MoonletPlanetUniforms &u) {
    if (u.iceCoverage <= 0.001) return 0.0;
    float sinLat = clamp(n.y, -1.0, 1.0);
    float legendre = (3.0 * sinLat * sinLat - 1.0) * 0.5;
    float insolation = 1.0 - 0.482 * legendre;
    // One hemisphere runs colder than the other.
    insolation += sinLat * u.polarAsymmetry * 0.22;
    // A lapse rate: height is the other way to be cold.
    float temperature = insolation - max(elevation, 0.0) * u.iceAltitude;
    // `iceCoverage` moves the isotherm across the whole range rather than scaling a radius,
    // so 0 leaves a world with no ice at all and 1 glaciates it to the equator.
    float freezing = mix(0.44, 1.34, u.iceCoverage);
    // The edge of an ice sheet follows weather and ground, never a line of latitude.
    float ragged = (moonletFBM(n * 3.6, u.seed + 331u, u.detail) - 0.5) * 0.26
                 + (moonletMicro(n * 16.0, u.seed + 337u) - 0.5) * 0.09;
    // A wide transition, because the edge of an ice sheet is a region and not a line: bare
    // ground shows through the margin long before the sheet gives out.
    return smoothstep(freezing + 0.13, freezing - 0.07, temperature + ragged);
}

float3 moonletWarp(float3 p, constant MoonletPlanetUniforms &u, float speed) {
    float3 q = float3(
        moonletFBM(p * 1.35 + float3(0, u.time * speed, 0), u.seed + 11u, u.detail),
        moonletFBM(p * 1.35 + float3(19.1, 3.7, u.time * speed), u.seed + 29u, u.detail),
        moonletFBM(p * 1.35 + float3(u.time * speed, 13.4, 7.2), u.seed + 47u, u.detail)
    );
    return p + (q - 0.5) * u.warpStrength * 2.2;
}

float moonletVortex(float3 normal, float3 center, float stretch) {
    float3 delta = normal - normalize(center);
    delta.y *= stretch;
    float radius = length(delta);
    float ring = exp(-radius * radius * 28.0);
    float curl = sin(atan2(delta.y, delta.x) * 3.0 + radius * 33.0);
    return ring * (0.58 + 0.42 * curl);
}

float3 moonletGas(float3 n, constant MoonletPlanetUniforms &u, thread float &elevation) {
    elevation = 0.0;
    float longitude = atan2(n.z, n.x);
    float latitude = asin(clamp(n.y, -1.0, 1.0));
    float bandFlow = sin(latitude * u.bandCount + sin(longitude * 2.0 + u.time * u.cloudSpeed) * u.turbulence);
    float3 stretched = float3(n.x * 0.52, n.y * 4.5, n.z * 0.52);
    stretched.xz = float2(
        stretched.x * cos(u.time * u.rotationSpeed) - stretched.z * sin(u.time * u.rotationSpeed),
        stretched.x * sin(u.time * u.rotationSpeed) + stretched.z * cos(u.time * u.rotationSpeed)
    );
    float3 warped = moonletWarp(stretched + float3(bandFlow * 0.13, 0, 0), u, u.cloudSpeed * 0.035);
    float broad = moonletFBM(warped * 1.25, u.seed, u.detail);
    float fine = moonletFBM(warped * 4.3 - float3(u.time * 0.008, 0, 0), u.seed + 83u, u.detail);
    float bands = smoothstep(-0.9 + u.bandSharpness * 0.5, 0.82, bandFlow * 0.72 + broad - 0.48);
    // Wisps an order of magnitude finer than the bands. Without them the bands are smooth
    // ribbons and the planet looks like a low-resolution picture of itself.
    float wisps = moonletMicro(warped * 13.0 - float3(u.time * 0.02, 0, 0), u.seed + 401u);
    float value = clamp(bands * 0.52 + broad * 0.44 + fine * 0.18
                        + (wisps - 0.5) * 0.22 * u.microDetail, 0.0, 1.0);
    float3 color = mix(u.color2.rgb, u.color1.rgb, smoothstep(0.08, 0.74, value));
    color = mix(color, u.color0.rgb, smoothstep(0.62, 1.0, value));
    float storms = 0;
    if (u.stormCount > 0.5) storms += moonletVortex(n, float3(0.85, 0.12, 0.52), 2.8);
    if (u.stormCount > 1.5) storms += moonletVortex(n, float3(-0.52, -0.38, 0.76), 3.6);
    if (u.stormCount > 2.5) storms += moonletVortex(n, float3(0.18, 0.58, 0.79), 2.2);
    if (u.stormCount > 3.5) storms += moonletVortex(n, float3(-0.84, 0.28, 0.46), 3.2);
    if (u.stormCount > 4.5) storms += moonletVortex(n, float3(0.56, -0.62, 0.55), 2.5);
    color = mix(color, u.color3.rgb, clamp(storms * u.stormStrength, 0.0, 0.88));
    // Polar hoods. A gas giant has no ground to freeze, but its poles really are darker and
    // greyer than its bands — the haze there is thicker and the banding gives out.
    float hood = smoothstep(0.74, 1.0, abs(n.y));
    return mix(color, mix(color, u.color2.rgb, 0.42) * 0.94, hood * 0.55);
}

float3 moonletOcean(float3 n, constant MoonletPlanetUniforms &u, thread float &elevation) {
    float3 warped = moonletWarp(n * 2.3, u, 0.018 * u.cloudSpeed);
    float continents = moonletFBM(warped, u.seed, u.detail);
    // Coastlines are fractal at every scale somebody zooms to; a smooth one is the single
    // clearest tell that a planet was drawn at low resolution.
    continents += (moonletMicro(warped * 9.0, u.seed + 421u) - 0.5) * 0.09 * u.microDetail;
    float coast = smoothstep(0.49 - u.featureAmount * 0.16, 0.58, continents);
    float terrain = moonletFBM(warped * 3.4, u.seed + 71u, u.detail);
    terrain += (moonletMicro(warped * 17.0, u.seed + 433u) - 0.5) * 0.2 * u.microDetail;
    elevation = (continents - 0.5) * 2.2 * coast;
    float3 ocean = mix(u.color2.rgb, u.color1.rgb, 0.52 + 0.48 * pow(max(0.0, n.y * 0.5 + 0.5), 2.0));
    float3 land = mix(u.color3.rgb * 0.48, u.color0.rgb * 0.78, terrain);
    float cloudNoise = moonletFBM(moonletWarp(n * 4.2 + float3(u.time * 0.018 * u.cloudSpeed, 0, 0), u, 0.02), u.seed + 193u, u.detail);
    cloudNoise += (moonletMicro(n * 15.0 + float3(u.time * 0.02 * u.cloudSpeed, 0, 0), u.seed + 449u) - 0.5) * 0.14 * u.microDetail;
    float clouds = smoothstep(0.64 - u.cloudCoverage * 0.24, 0.79, cloudNoise);
    return mix(mix(ocean, land, coast), u.color0.rgb, clouds * 0.72);
}

float3 moonletFrozen(float3 n, constant MoonletPlanetUniforms &u, thread float &elevation) {
    float3 warped = moonletWarp(n * 3.5, u, 0.006);
    float ridges = 1.0 - abs(moonletFBM(warped, u.seed, u.detail) * 2.0 - 1.0);
    float cracks = pow(1.0 - abs(moonletNoise(warped * 4.5, u.seed + 101u) * 2.0 - 1.0), 8.0);
    // A second, finer fracture set. Real ice shells crack at more than one scale.
    cracks = max(cracks, pow(1.0 - abs(moonletMicro(warped * 13.0, u.seed + 457u) * 2.0 - 1.0), 11.0) * 0.8 * u.microDetail);
    elevation = ridges;
    float3 ice = mix(u.color2.rgb, u.color1.rgb, ridges);
    ice = mix(ice, u.color0.rgb, smoothstep(0.58, 0.94, ridges));
    return mix(ice, u.color2.rgb * 0.35, cracks * u.featureAmount);
}

/// Craters as a height field: negative in the bowl, positive on the rim.
///
/// The rim is the whole point. A crater drawn as a dark circle reads as a stain; what makes
/// it read as a hole is that the ground immediately outside it is *raised*, so the light
/// catches one side of the ring and the other side falls away.
///
/// Cells that fail the density test cost one hash and are skipped, which is what keeps a
/// 27-cell neighbourhood affordable next to the six-octave noise this shader already runs.
/// Where the star is.
///
/// Computed in one place because three call sites need it — the surface relief for rock and
/// for desert, and the shading itself — and a day/night cycle that only some of them knew
/// about would light the craters from one direction and the planet from another.
float3 moonletLight(constant MoonletPlanetUniforms &u) {
    float azimuth = u.lightAzimuth + u.time * u.dayNightSpeed;
    return normalize(float3(cos(u.lightElevation) * cos(azimuth),
                            sin(u.lightElevation),
                            cos(u.lightElevation) * sin(azimuth)));
}

float moonletCraters(float3 p, uint seed, float density) {
    float3 base = floor(p);
    float height = 0.0;
    for (int dz = -1; dz <= 1; dz++) {
        for (int dy = -1; dy <= 1; dy++) {
            for (int dx = -1; dx <= 1; dx++) {
                float3 cell = base + float3(dx, dy, dz);
                if (moonletHash(cell, seed) > density) continue;
                float3 jitter = float3(moonletHash(cell, seed + 17u),
                                       moonletHash(cell, seed + 41u),
                                       moonletHash(cell, seed + 89u)) - 0.5;
                float3 centre = cell + 0.5 + jitter * 0.66;
                float radius = mix(0.2, 0.46, moonletHash(cell, seed + 131u));
                float d = length(p - centre) / radius;
                if (d >= 1.0) continue;
                float bowl = -(1.0 - smoothstep(0.0, 0.7, d));
                float rim = exp(-pow((d - 0.8) * 6.5, 2.0));
                height += (bowl + rim * 0.85) * smoothstep(1.0, 0.84, d);
            }
        }
    }
    return height;
}

/// Ridged multifractal. Folding the noise about its midpoint turns rounded hills into
/// crests, which is what a mountain range has and a sum of octaves does not.
float moonletRidged(float3 p, uint seed, float detail) {
    float value = 0.0;
    float amplitude = 0.5;
    float frequency = 1.0;
    for (uint octave = 0; octave < 4; octave++) {
        float n = 1.0 - abs(moonletNoise(p * frequency, seed + octave * 61u) * 2.0 - 1.0);
        value += n * n * amplitude;
        frequency *= 2.07;
        amplitude *= mix(0.42, 0.56, detail);
    }
    return value;
}

/// The rock surface as one number, so it can be sampled twice — once here and once a step
/// toward the light — and turned into directional relief.
float moonletRockElevation(float3 n, constant MoonletPlanetUniforms &u, thread float &terrain, thread float &highlands, thread float &craters) {
    float3 warped = moonletWarp(n * 3.2, u, 0.002);
    terrain = moonletFBM(warped, u.seed, u.detail);
    highlands = moonletRidged(warped * 1.7, u.seed + 71u, u.detail);
    // Three scales. Basins are rare and wide, the smallest pit everything; one scale alone
    // reads as a repeating pattern rather than a bombarded surface.
    craters = moonletCraters(n * 3.1, u.seed + 211u, 0.30)
            + moonletCraters(n * 7.7, u.seed + 307u, 0.38) * 0.5
            + moonletCraters(n * 17.0, u.seed + 419u, 0.46) * 0.24;
    craters *= u.featureAmount;
    return terrain * 0.5 + highlands * 0.5 + craters * 0.55;
}

float3 moonletRock(float3 n, constant MoonletPlanetUniforms &u, bool molten, thread float &elevation) {
    elevation = 0.0;
    if (molten) {
        float3 warped = moonletWarp(n * 3.2, u, 0.012);
        float terrain = moonletFBM(warped, u.seed, u.detail);
        float cells = moonletNoise(warped * 3.8, u.seed + 157u);
        float ridges = 1.0 - abs(cells * 2.0 - 1.0);
        float cracks = pow(ridges, mix(12.0, 5.0, u.featureAmount));
        float3 crust = mix(u.color2.rgb, u.color1.rgb * 0.28, terrain);
        float3 lava = mix(u.color1.rgb, u.color0.rgb, pow(cracks, 0.52));
        return mix(crust, lava, clamp(cracks * 1.5, 0.0, 1.0));
    }

    float terrain, highlands, craters;
    elevation = moonletRockElevation(n, u, terrain, highlands, craters);

    // One extra sample, a step toward the light, is what turns a height field into a lit
    // surface. Perturbing the shading normal properly would cost three; this costs one and
    // is the difference between a crater that is a hole and a crater that is a smudge.
    float3 light = moonletLight(u);
    float t2, h2, c2;
    float lit = moonletRockElevation(normalize(n + light * 0.03), u, t2, h2, c2);
    float relief = clamp((lit - elevation) * 3.2, -0.8, 0.8);

    // Canyons. `cracks` was computed and thrown away here for a long time, which is most of
    // why this archetype was a brown ball.
    float cells = moonletNoise(n * 6.4, u.seed + 157u);
    float cracks = pow(1.0 - abs(cells * 2.0 - 1.0), mix(14.0, 5.0, u.featureAmount));
    // Regolith. Everything above is metres across; this is what the ground looks like.
    float grain = (moonletMicro(n * 34.0, u.seed + 463u) - 0.5) * 0.16 * u.microDetail;

    float3 color = mix(u.color2.rgb, u.color1.rgb, smoothstep(0.22, 0.74, terrain));
    color = mix(color, u.color0.rgb, smoothstep(0.28, 0.78, highlands) * 0.85);
    color = mix(color, u.color3.rgb * 0.7, cracks * 0.4 * u.featureAmount);
    color *= 1.0 + relief * 0.6 + grain;
    // Crater floors keep the shadow colour rather than only going dark, so a bowl reads as
    // ground in shade instead of a hole punched in the image.
    color = mix(color, u.color2.rgb * 0.62, clamp(-craters, 0.0, 1.0) * 0.5);
    return max(color, 0.0);
}

/// Deserts are not rocky worlds with a warmer palette.
///
/// What makes sand read as sand is that it is *anisotropic*: wind builds dunes in long
/// ridges across the prevailing direction, so the noise is sampled with latitude compressed
/// rather than evenly. Sharing `moonletRock` is why this archetype and `rocky` used to be
/// the same picture twice.
float moonletDesertElevation(float3 n, constant MoonletPlanetUniforms &u, thread float &sand, thread float &bedrock) {
    // Dune fields, stretched along latitude by the wind.
    float3 stretched = float3(n.x, n.y * 3.6, n.z);
    float3 warped = moonletWarp(stretched * 2.2, u, 0.003);
    float dunes = moonletRidged(warped * 1.5, u.seed + 53u, u.detail);
    // The crests themselves. Sharp on one side and soft on the other is what a dune is.
    float crest = pow(0.5 + 0.5 * sin(dunes * 9.0), 2.2);

    // Where the sand is deep and where the bedrock shows through.
    float basins = moonletFBM(moonletWarp(n * 1.8, u, 0.001), u.seed + 97u, u.detail);
    sand = smoothstep(0.36, 0.58, basins);
    bedrock = moonletCraters(n * 5.2, u.seed + 233u, 0.28) * u.featureAmount * 0.6
            + moonletRidged(n * 3.2, u.seed + 149u, u.detail) * 0.9;

    return mix(bedrock, dunes * 0.85 + crest * 0.28, sand);
}

float3 moonletDesert(float3 n, constant MoonletPlanetUniforms &u, thread float &elevation) {
    float sand, bedrock;
    elevation = moonletDesertElevation(n, u, sand, bedrock);

    // The same one-extra-sample relief the rock surface uses. Without it a dune field is a
    // pattern printed on a ball rather than something the light crosses.
    float3 light = moonletLight(u);
    float s2, b2;
    float lit = moonletDesertElevation(normalize(n + light * 0.03), u, s2, b2);
    float relief = clamp((lit - elevation) * 2.6, -0.7, 0.7);

    float3 deepSand = mix(u.color1.rgb, u.color0.rgb, smoothstep(0.15, 0.85, elevation));
    float3 rock = mix(u.color2.rgb, u.color3.rgb * 0.66, smoothstep(0.1, 0.8, bedrock));
    float3 color = mix(rock, deepSand, sand);
    color *= 1.0 + relief * 0.5;

    // A dust veil, and only over the deep sand — a dust storm rises off the sand seas, not
    // off bare rock. It was over everything, which is what flattened the whole surface.
    float dust = smoothstep(0.55, 0.95, moonletFBM(moonletWarp(n * 2.6 + float3(u.time * 0.01 * u.cloudSpeed, 0, 0), u, 0.01), u.seed + 181u, u.detail));
    return mix(color, u.color0.rgb * 0.94, dust * u.cloudCoverage * sand * 0.3);
}


/// Where a world is settled, and how brightly, on the side of it facing away from the star.
///
/// What makes lights read as cities rather than as speckle is where they are *not*. Never on
/// water. Thinning inland — population follows coasts and rivers, so the brightest band sits
/// just inside the shoreline and the interior goes dark. And clustered: a region is either
/// settled or it is empty, and the towns inside a settled region are scattered around the
/// cities rather than spread evenly over the continent.
///
/// Three scales do that: one that decides which regions are inhabited at all, one for cities,
/// one for the towns between them.
float moonletCityLights(float3 n, float elevation, constant MoonletPlanetUniforms &u) {
    if (u.life < 2u) return 0.0;

    // Land only, and brightest near the shore. `elevation` is already zero over water for the
    // surfaces that have water, and low ground everywhere else.
    float land = smoothstep(0.0, 0.1, elevation);
    float coastal = land * (1.0 - smoothstep(0.05, 0.5, elevation));
    float habitable = clamp(land * 0.3 + coastal * 1.0, 0.0, 1.0);
    if (habitable <= 0.002) return 0.0;

    float region = moonletFBM(n * 3.2, u.seed + 521u, u.detail);
    float settled = smoothstep(0.4, 0.62, region);
    if (settled <= 0.002) return 0.0;

    float cities = smoothstep(0.62, 0.86, moonletMicro(n * 14.0, u.seed + 527u));
    float towns = smoothstep(0.58, 0.84, moonletMicro(n * 44.0, u.seed + 523u));

    // A civilisation that has just learned to light its streets does not light all of them.
    float reach = (u.life == 2u) ? 0.4 : 1.0;
    return habitable * settled * (cities * 1.15 + towns * 0.5) * reach;
}

/// What life does to the ground in daylight.
///
/// Level one is the interesting one: no lights, nothing built, just a world whose land has
/// gone faintly green where it is low and wet. It is the difference between Mars and a Mars
/// with lichen on it, and it should read at a glance without turning the planet into a lawn.
float3 moonletLivingGround(float3 albedo, float3 n, float elevation, constant MoonletPlanetUniforms &u) {
    if (u.life == 0u) return albedo;
    float land = smoothstep(-0.02, 0.16, elevation);
    // Life pools in the low, wet ground and thins as the land rises.
    float lowland = land * (1.0 - smoothstep(0.2, 0.85, elevation));
    float patches = smoothstep(0.4, 0.72, moonletFBM(n * 2.6, u.seed + 541u, u.detail));
    float spread = clamp(lowland * patches, 0.0, 1.0);
    float strength = (u.life == 1u) ? 0.34 : (u.life == 2u ? 0.5 : 0.6);
    return mix(albedo, mix(albedo, u.lifeColor.rgb, 0.75), spread * strength);
}

/// The radial structure of a ring system, in planet radii, and it is Saturn's.
///
/// The boundaries are measured, not invented: the C ring begins at 1.235 planet radii, the
/// B ring — the bright one — runs 1.525 to 1.95, the Cassini Division is the near-empty lane
/// from 1.95 to 2.025, and the A ring runs out to 2.27 with the Encke gap cut into it at
/// 2.214 and the Keeler gap at 2.265. The optical depths are Cassini's too: about 0.1
/// through the C ring and the Division, 0.4 to 2.5 across the B ring, 0.4 to 1.0 across the A.
///
/// Real numbers rather than a pretty gradient is what makes a ringed planet read as a
/// photograph of one. The Division especially is not decoration — it is the single feature
/// that says "Saturn" faster than anything else in the frame.
///
/// The recipe's inner and outer radii *stretch* this profile rather than replacing it, so a
/// ring system that is narrower or wider than Saturn's still has Saturn's anatomy.
/// `lod` is how much of the profile one pixel spans, in the same units as `rs`. Ringlets
/// finer than that are averaged away instead of aliasing: near edge-on a single pixel can
/// cross fifty ringlets, and drawing them all is how a ring system turns into moiré.
float moonletRingProfile(float r, float lod, constant MoonletPlanetUniforms &u, thread float3 &tint) {
    float span = max(u.ringOuterRadius - u.ringInnerRadius, 0.02);
    float rs = 1.235 + (r - u.ringInnerRadius) / span * (2.27 - 1.235);
    tint = float3(0.0);
    if (rs < 1.235 || rs > 2.27) return 0.0;

    float tau;
    float3 c;
    if (rs < 1.525) {
        // C ring: thin, dark, and greyer than the rest — less ice, more of whatever else.
        tau = mix(0.04, 0.17, smoothstep(1.235, 1.525, rs));
        c = float3(0.60, 0.63, 0.70);
    } else if (rs < 1.95) {
        // B ring: the bright one, and the only part thick enough to be genuinely opaque.
        float t = (rs - 1.525) / 0.425;
        tau = mix(2.3, 0.85, clamp(abs(t - 0.42) * 1.7, 0.0, 1.0));
        c = float3(1.0, 0.95, 0.84);
    } else if (rs < 2.025) {
        tau = 0.09;                                   // Cassini Division
        c = float3(0.72, 0.71, 0.71);
    } else {
        tau = 0.6;                                    // A ring
        c = float3(0.93, 0.89, 0.81);
        if (rs > 2.214 && rs < 2.221) tau = 0.025;    // Encke gap
        if (rs > 2.263 && rs < 2.267) tau = 0.04;     // Keeler gap
    }

    // Ringlets. The real rings are banded at every scale the eye can resolve, and a flat
    // annulus reads as a plastic hoop no matter how correct its edges are.
    // Each scale is faded out once a pixel is wide enough to cross it. A band averages to
    // its mean, which is 0.5, so the fade goes to 0.5 rather than to zero.
    float fade26 = 1.0 - smoothstep(0.35 / 26.0, 1.2 / 26.0, lod);
    float fade95 = 1.0 - smoothstep(0.35 / 95.0, 1.2 / 95.0, lod);
    float fade340 = 1.0 - smoothstep(0.35 / 340.0, 1.2 / 340.0, lod);
    float coarse = mix(0.5, moonletNoise(float3(rs * 26.0, 3.1, 7.7), u.seed + 613u), fade26);
    float bands = mix(0.5, moonletNoise(float3(rs * 95.0, 1.7, 4.3), u.seed + 809u), fade95);
    float fine = mix(0.5, moonletNoise(float3(rs * 340.0, 1.3, 2.9), u.seed + 977u), fade340);
    float ringlets = coarse * 0.42 + bands * 0.4 + fine * 0.18;
    tau *= mix(1.0, 0.28 + ringlets * 1.55, u.ringDetail);

    // Soft inner and outer edges, widened to at least a pixel so neither ends on a stair.
    float edge = max(lod * 1.5, 0.012);
    tau *= smoothstep(1.235, 1.235 + edge * 4.0, rs)
         * (1.0 - smoothstep(2.27 - edge * 6.0, 2.27, rs) * 0.9);

    tint = c;
    return max(tau, 0.0);
}

fragment half4 moonletPlanetFragment(MoonletPlanetVertexOut input [[stage_in]], constant MoonletPlanetUniforms &u [[buffer(0)]]) {
    // A ringed planet is wider than its own disc, so the canvas is measured in planet radii
    // and zooms out to hold the rings. Without rings the framing is exactly what it was.
    float ringScale = (u.ringOpacity > 0.001) ? max(1.0, u.ringOuterRadius * 1.04) : 1.0;
    float2 p = input.uv * 2.0 - 1.0;
    p.x *= u.viewportSize.x / max(u.viewportSize.y, 1.0);
    p *= ringScale;

    // The lighting works in a space where screen-up is -y, so everything geometric works
    // there too. Mixing the two is how the terminator and the ring shadow end up disagreeing
    // about which side the star is on.
    float2 q = float2(p.x, -p.y);
    float radiusSquared = dot(q, q);
    bool hitsPlanet = radiusSquared <= 1.0;
    float surfaceZ = sqrt(max(0.0, 1.0 - radiusSquared));

    float3 light = moonletLight(u);

    // --- rings ---------------------------------------------------------------------
    //
    // The ring plane is the planet's equator and the camera is orthographic along -z, so the
    // intersection has a closed form and costs no marching: a ray through (q.x, q.y) meets a
    // plane with normal (0, cos t, sin t) at a point whose distance from the centre is
    // sqrt(q.x² + (q.y / sin t)²). Everything else — which side of the planet that point is
    // on, whether the planet shadows it, whether it shadows the planet — falls out of it.
    //
    // `axialTilt` is the planet's pole, and the rings lie in its equator — they are not two
    // settings that happen to agree. 0 points the pole up the screen and shows the rings
    // edge-on; π/2 points it at the camera and opens them fully. A planet with no rings is
    // unaffected at 0, which is every preset that had none.
    float sinT = sin(u.axialTilt);
    float cosT = cos(u.axialTilt);
    float sinSafe = max(abs(sinT), 0.02) * (sinT < 0.0 ? -1.0 : 1.0);
    float3 ringNormal = normalize(float3(0.0, cosT, sinT));
    float3 ringPoint = float3(q.x, q.y, -q.y * cosT / sinSafe);
    float ringRadius = length(ringPoint);

    float3 ringRGB = float3(0.0);
    float ringAlpha = 0.0;
    bool ringInFront = true;

    if (u.ringOpacity > 0.001) {
        float3 tint;
        // The footprint of this pixel in profile units, which is what stops the ringlets
        // aliasing when the system is nearly edge-on.
        float lod = fwidth(ringRadius) * (2.27 - 1.235) / max(u.ringOuterRadius - u.ringInnerRadius, 0.02);
        float tau = moonletRingProfile(ringRadius, lod, u, tint) * u.ringOpacity;
        if (tau > 0.0005) {
            // How much material the eye is looking through. Edge-on is a long path through
            // the same ring, which is why a nearly-closed ring system looks solid.
            float mu = max(abs(sinT), 0.03);
            ringAlpha = 1.0 - exp(-tau / mu);

            float lightSide = dot(ringNormal, light);
            float viewSide = ringNormal.z;
            float3 base = tint * u.ringColor.rgb;

            if (lightSide * viewSide > 0.0) {
                // The lit face. The opposition surge is real and is why Saturn's rings jump
                // in brightness when the sun is directly behind the observer.
                float surge = 1.0 + 0.45 * pow(max(light.z, 0.0), 3.0);
                // Single-scattering brightness. This is what keeps the ringlets visible
                // where the alpha above has already saturated to one.
                float scatter = 1.0 - exp(-tau * 1.9);
                ringRGB = base * (0.16 + 0.84 * abs(lightSide)) * surge * (0.25 + 0.9 * scatter);
            } else {
                // The unlit face, seen by transmitted light: the thin C ring glows and the
                // thick B ring goes dark, which is the reverse of how they look lit.
                ringRGB = base * (0.08 + 0.3 * abs(lightSide)) * exp(-tau * 0.85);
            }

            // The planet's shadow across the rings, a cylinder because the star is far away.
            float along = dot(ringPoint, light);
            float perp = length(ringPoint - along * light);
            if (along < 0.0) ringRGB *= mix(0.09, 1.0, smoothstep(0.9, 1.3, perp));

            ringRGB = 1.0 - exp(-ringRGB * u.exposure);
            ringInFront = !hitsPlanet || (ringPoint.z > surfaceZ);
        }
    }

    // Premultiplied throughout, so a semi-transparent ring composites over the planet and
    // over nothing with the same arithmetic.
    float3 color = float3(0.0);
    float alpha = 0.0;

    if (!ringInFront && ringAlpha > 0.0) {
        color = ringRGB * ringAlpha;
        alpha = ringAlpha;
    }

    if (hitsPlanet) {
        float3 normal = normalize(float3(q.x, q.y, surfaceZ));

        // Into the planet's own frame, where +y is the pole. Bands, ice and the day's
        // rotation are all about the axis, so they are computed after this and not before:
        // a tilted planet whose weather stayed level is the giveaway that the tilt is paint.
        float3 poleAxis = ringNormal;
        float3 poleRight = float3(1.0, 0.0, 0.0);
        float3 poleForward = float3(0.0, sinT, -cosT);
        float3 oriented = float3(dot(normal, poleRight), dot(normal, poleAxis), dot(normal, poleForward));

        // The clock turns the planet; `rotationPhase` is added to it rather than folded into
        // the time, so dragging a planet that is not spinning still turns it.
        float spin = u.time * u.rotationSpeed + u.rotationPhase;
        float c = cos(spin);
        float s = sin(spin);
        float3 surfaceNormal = float3(oriented.x * c - oriented.z * s, oriented.y, oriented.x * s + oriented.z * c);
        float3 albedo;
        float elevation = 0.0;
        bool gaseous = false;
        if (u.archetype == 0u || u.archetype == 1u || u.archetype == 7u || u.archetype == 9u) {
            albedo = moonletGas(surfaceNormal, u, elevation);
            gaseous = true;
        } else if (u.archetype == 2u || u.archetype == 8u) {
            albedo = moonletOcean(surfaceNormal, u, elevation);
        } else if (u.archetype == 3u) {
            albedo = moonletFrozen(surfaceNormal, u, elevation);
        } else if (u.archetype == 6u) {
            albedo = moonletDesert(surfaceNormal, u, elevation);
        } else {
            albedo = moonletRock(surfaceNormal, u, u.archetype == 5u, elevation);
        }

        // Life sits on ground too, so the gas giants skip both of these.
        if (!gaseous) albedo = moonletLivingGround(albedo, surfaceNormal, elevation, u);

        // Ice sits on ground, so a gas giant gets none — it gets the polar hood instead,
        // which `moonletGas` has already applied.
        if (!gaseous) {
            float ice = moonletPolarIce(surfaceNormal, elevation, u);
            if (ice > 0.0) {
                float3 sheet = u.iceColor.rgb;
                // Sastrugi: wind-carved ridges. An ice sheet photographed from orbit is not
                // a white area, it is a textured one, and a flat fill is what makes a cap
                // read as a sticker.
                float grain = moonletMicro(surfaceNormal * 24.0, u.seed + 467u) - 0.5;
                float drift = moonletFBM(surfaceNormal * float3(2.0, 7.0, 2.0), u.seed + 471u, u.detail) - 0.5;
                sheet *= 1.0 + grain * 0.16 * u.microDetail + drift * 0.13;
                // Ice over dark ground is darker: it is thin at the margin and the sea shows
                // through, which is the difference between a sheet and a coat of paint.
                sheet = mix(sheet, sheet * 0.55 + albedo * 0.45, 0.28);
                // Height catches the light.
                sheet *= mix(0.88, 1.06, clamp(elevation * 0.5 + 0.5, 0.0, 1.0));
                albedo = mix(albedo, sheet, ice * 0.94);
            }
        }

        float diffuse = dot(normal, light);
        float day = smoothstep(-0.24 - u.atmosphereDensity * 0.12, 0.18, diffuse);
        float softLight = 0.13 + max(diffuse, 0.0) * 0.87;
        float rim = pow(1.0 - max(normal.z, 0.0), mix(4.6, 1.6, u.atmosphereDensity));
        float specular = pow(max(dot(reflect(-light, normal), float3(0, 0, 1)), 0.0), mix(72.0, 9.0, u.roughness)) * (1.0 - u.roughness);

        // The rings' shadow on the planet, which is the other half of the pair and the one
        // that sells the geometry: a band of shadow that curves with the planet and carries
        // the Cassini Division across it as a bright stripe.
        float ringShade = 1.0;
        if (u.ringOpacity > 0.001) {
            float denom = dot(light, ringNormal);
            if (abs(denom) > 0.002) {
                float travel = -dot(normal, ringNormal) / denom;
                if (travel > 0.0) {
                    float3 tint;
                    float shadowRadius = length(normal + travel * light);
                    float shadowLod = fwidth(shadowRadius) * (2.27 - 1.235) / max(u.ringOuterRadius - u.ringInnerRadius, 0.02);
                    float tau = moonletRingProfile(shadowRadius, shadowLod, u, tint) * u.ringOpacity;
                    // Softened across the terminator: a hard-edged band reads as a decal
                    // rather than as something cast from above.
                    ringShade = exp(-tau / max(abs(denom), 0.06));
                    ringShade = mix(1.0, ringShade, smoothstep(0.0, 0.25, travel));
                }
            }
        }

        float3 planet = albedo * softLight * mix(0.2, 1.0, day) * mix(1.0, ringShade, 0.9);

        // City lights, added as emission before the tonemap so they bloom the way a bright
        // thing does rather than being pasted on at full strength afterwards.
        //
        // Squared night, so they come up through the last of the dusk instead of switching on
        // at the terminator — and they are not shadowed by the rings, because a city under a
        // ring's shadow is a city at night, which is when it is lit.
        if (!gaseous && u.life >= 2u) {
            float night = 1.0 - day;
            float lit = moonletCityLights(surfaceNormal, elevation, u) * night * night;
            if (lit > 0.0) {
                // Sodium orange with the cooler light a further-along civilisation builds.
                float3 warm = float3(1.0, 0.72, 0.36);
                float3 cool = float3(0.78, 0.86, 1.0);
                float3 glow = mix(warm, cool, (u.life == 3u) ? 0.35 : 0.12);
                // Emission, and it has to be strong: the night side is nearly black and the
                // tonemap below compresses everything, so a value that looks right before it
                // disappears after.
                planet += glow * lit * 7.0;
            }
        }
        planet += u.color0.rgb * specular * 0.4 * ringShade;
        planet += u.atmosphereColor.rgb * rim * u.atmosphereGlow * (0.3 + day * 0.7);
        planet = 1.0 - exp(-planet * u.exposure);

        float planetAlpha = smoothstep(1.0, 0.975, radiusSquared);
        color = planet * planetAlpha + color * (1.0 - planetAlpha);
        alpha = planetAlpha + alpha * (1.0 - planetAlpha);
    }

    if (ringInFront && ringAlpha > 0.0) {
        color = ringRGB * ringAlpha + color * (1.0 - ringAlpha);
        alpha = ringAlpha + alpha * (1.0 - ringAlpha);
    }

    if (alpha <= 0.0) return half4(0);
    return half4(half3(color), half(alpha));
}
