float4 frag(v2f i) : SV_Target
{
    if (i.uv.y < 0.005)
    {
        return i.uv.x < (foamCountBuffer[0] / (float)foamMax);
    }
    float3 normal = tex2D(Normals, i.uv).xyz;
    float4 packedData = tex2D(Comp, i.uv);
    float depthSmooth = packedData.r;
    float thickness = packedData.g;
    float thickness_hard = packedData.b;
    float depth_hard = packedData.a;
    float4 bg = tex2D(_MainTex, float2(i.uv.x, i.uv.y));
    float foam = bg.r;
    float foamDepth = bg.b;
    float3 viewDirWorld = WorldViewDir(i.uv);
    float3 world = SampleEnvironmentAA(_WorldSpaceCameraPos, viewDirWorld);
    if (depthSmooth > 1000) return float4(world, 1) * (1 - foam) + foam;
    float3 hitPos = _WorldSpaceCameraPos.xyz + viewDirWorld * depthSmooth;
    float3 smoothEdgeNormal = SmoothEdgeNormals(normal, hitPos, boundsSize).xyz;
    normal = normalize(normal + smoothEdgeNormal * 6 * max(0, dot(normal, smoothEdgeNormal.xyz)));
    const float ambientLight = 0.3;
    float shading = dot(normal, dirToSun) * 0.5 + 0.5;
    shading = shading * (1 - ambientLight) + ambientLight;
    LightResponse lightResponse = CalculateReflectionAndRefraction(viewDirWorld, normal, 1, 1.33);
    float3 reflectDir = reflect(viewDirWorld, normal);
    float3 exitPos = hitPos + lightResponse.refractDir * thickness * refractionMultiplier;
    exitPos += lightResponse.refractDir * max(0, floorPos.y + floorSize.y - exitPos.y) / lightResponse.refractDir.y;
    float3 transmission = exp(-thickness * extinctionCoefficients);
    float3 reflectCol = SampleEnvironmentAA(hitPos, lightResponse.reflectDir);
    float3 refractCol = SampleEnvironmentAA(exitPos, viewDirWorld);
    refractCol = refractCol * (1 - foam) + foam;
    refractCol *= transmission;
    float3 col = lerp(reflectCol, refractCol, lightResponse.refractWeight);
    return float4(col, 1);
}
float CalculateScreenSpaceRadius(float worldRadius, float depth, int imageWidth)
{
    float widthScale = UNITY_MATRIX_P._m00; 
    float pxPerMeter = (imageWidth * widthScale) / (2 * depth);
    return abs(pxPerMeter) * worldRadius;
}
float CalculateReflectance(float3 inDir, float3 normal, float iorA, float iorB)
{
    float refractRatio = iorA / iorB;
    float cosAngleIn = -dot(inDir, normal);
    float sinSqrAngleOfRefraction = refractRatio * refractRatio * (1 - cosAngleIn * cosAngleIn);
    if (sinSqrAngleOfRefraction >= 1) return 1; 
    float cosAngleOfRefraction = sqrt(1 - sinSqrAngleOfRefraction);
    float rPerpendicular = (iorA * cosAngleIn - iorB * cosAngleOfRefraction) / (iorA * cosAngleIn + iorB * cosAngleOfRefraction);
    rPerpendicular *= rPerpendicular;
    float rParallel = (iorB * cosAngleIn - iorA * cosAngleOfRefraction) / (iorB * cosAngleIn + iorA * cosAngleOfRefraction);
    rParallel *= rParallel;
    return (rPerpendicular + rParallel) / 2;
}
float3 Refract(float3 inDir, float3 normal, float iorA, float iorB)
{
    float refractRatio = iorA / iorB;
    float cosAngleIn = -dot(inDir, normal);
    float sinSqrAngleOfRefraction = refractRatio * refractRatio * (1 - cosAngleIn * cosAngleIn);
    if (sinSqrAngleOfRefraction > 1) return 0; 
    float3 refractDir = refractRatio * inDir + (refractRatio * cosAngleIn - sqrt(1 - sinSqrAngleOfRefraction)) * normal;
    return refractDir;
}
float3 Reflect(float3 inDir, float3 normal)
{
    return inDir - 2 * dot(inDir, normal) * normal;
}
LightResponse CalculateReflectionAndRefraction(float3 inDir, float3 normal, float iorA, float iorB)
{
    LightResponse result;
    result.reflectWeight = CalculateReflectance(inDir, normal, iorA, iorB);
    result.refractWeight = 1 - result.reflectWeight;
    result.reflectDir = Reflect(inDir, normal);
    result.refractDir = Refract(inDir, normal, iorA, iorB);
    return result;
}
float3 SampleEnvironment(float3 pos, float3 dir)
{
    HitInfo floorInfo = RayBox(pos, dir, floorPos, floorSize);
    if (floorInfo.didHit)
    {
        float2 texCoord = floorInfo.hitPoint.xz * _TextureScale;
        float3 textureColor = tex2D(_TextureMap, texCoord).rgb;
        float4 shadowClip = mul(shadowVP, float4(floorInfo.hitPoint, 1));
        shadowClip /= shadowClip.w;
        float2 shadowUV = shadowClip.xy * 0.5 + 0.5;
        float shadowEdgeWeight = shadowUV.x >= 0 && shadowUV.x <= 1 && shadowUV.y >= 0 && shadowUV.y <= 1;
        float3 shadow = tex2D(ShadowMap, shadowUV).r * shadowEdgeWeight;
        shadow = exp(-shadow * 1 * extinctionCoefficients);
        float ambientLight = 0.17;
        shadow = shadow * (1 - ambientLight) + ambientLight;
        return textureColor * shadow;
    }
    return SampleSky(dir);
}