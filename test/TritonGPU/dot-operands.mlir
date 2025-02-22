// RUN: triton-opt %s -split-input-file -tritongpu-optimize-dot-operands -tritongpu-remove-layout-conversions -canonicalize | FileCheck %s

#Cv2 = #triton_gpu.mma<{versionMajor = 2, warpsPerCTA = [4, 1]}>
#Av2 = #triton_gpu.dot_op<{opIdx = 0, parent = #Cv2, kWidth=2}>
#Bv2 = #triton_gpu.dot_op<{opIdx = 1, parent = #Cv2, kWidth=2}>
#Cv1 = #triton_gpu.mma<{versionMajor = 1, warpsPerCTA = [4, 1]}>
#Av1 = #triton_gpu.dot_op<{opIdx = 0, parent = #Cv1}>
#Bv1 = #triton_gpu.dot_op<{opIdx = 1, parent = #Cv1}>
#ALR = #triton_gpu.blocked<{sizePerThread = [1, 4], threadsPerWarp = [4, 8], warpsPerCTA = [4, 1], order = [1, 0]}>
#ALC = #triton_gpu.blocked<{sizePerThread = [1, 4], threadsPerWarp = [4, 8], warpsPerCTA = [4, 1], order = [0, 1]}>
#BLR = #triton_gpu.blocked<{sizePerThread = [1, 4], threadsPerWarp = [1, 32], warpsPerCTA = [4, 1], order = [1, 0]}>
#BLC = #triton_gpu.blocked<{sizePerThread = [1, 4], threadsPerWarp = [1, 32], warpsPerCTA = [4, 1], order = [0, 1]}>

module attributes {"triton_gpu.num-warps" = 4 : i32} {

// CHECK: tt.func @push_elementwise1
// CHECK: %[[ALOAD:.*]] = tt.load %arg0
// CHECK: %[[ACVT:.*]] = triton_gpu.convert_layout %[[ALOAD]] {{.*}} #triton_gpu.dot_op<{opIdx = 0, parent = #mma, kWidth = 4}>>
// CHECK: %[[AF8E5:.*]] = tt.bitcast %[[ACVT]] {{.*}} #triton_gpu.dot_op<{opIdx = 0, parent = #mma, kWidth = 4}>>
// CHECK: %[[AF16:.*]] = tt.fp_to_fp %[[AF8E5]] {{.*}} #triton_gpu.dot_op<{opIdx = 0, parent = #mma, kWidth = 4}>>
// CHECK: %[[BCVT:.*]] = triton_gpu.convert_layout %{{.*}} : {{.*}} tensor<16x16xf16, #triton_gpu.dot_op<{opIdx = 1, parent = #mma, kWidth = 4}>>
// CHECK: %[[C:.*]] = tt.dot %[[AF16]], %[[BCVT]]
// CHECK-SAME: tensor<16x16xf16, #triton_gpu.dot_op<{opIdx = 0, parent = #mma, kWidth = 4}>> * tensor<16x16xf16, #triton_gpu.dot_op<{opIdx = 1, parent = #mma, kWidth = 4}>> -> tensor<16x16xf32, #mma>
// CHECK: tt.return %[[C]] : tensor<16x16xf32, #mma>
tt.func @push_elementwise1(
                   %pa: tensor<16x16x!tt.ptr<i8>, #ALR> {tt.divisibility=16: i32, tt.contiguity=2 : i32},
                   %pb: tensor<16x16x!tt.ptr<f16>, #BLC> {tt.divisibility=16: i32, tt.contiguity=2 : i32},
                   %c: tensor<16x16xf32, #Cv2>) -> tensor<16x16xf32, #Cv2>{
  %ai8 = tt.load %pa {cache = 1 : i32, evict = 1 : i32, isVolatile = false} : tensor<16x16xi8, #ALR>
  %b = tt.load %pb {cache = 1 : i32, evict = 1 : i32, isVolatile = false} : tensor<16x16xf16, #BLC>
  %af8 = tt.bitcast %ai8: tensor<16x16xi8, #ALR> -> tensor<16x16xf8E5M2, #ALR>
  %a = tt.fp_to_fp %af8: tensor<16x16xf8E5M2, #ALR> -> tensor<16x16xf16, #ALR>
  %dota = triton_gpu.convert_layout %a : (tensor<16x16xf16, #ALR>) -> tensor<16x16xf16, #Av2>
  %dotb = triton_gpu.convert_layout %b : (tensor<16x16xf16, #BLC>) -> tensor<16x16xf16, #Bv2>
  %newc = tt.dot %dota, %dotb, %c {allowTF32 = true, transA = false, transB = false} : tensor<16x16xf16, #Av2> * tensor<16x16xf16, #Bv2> -> tensor<16x16xf32, #Cv2>
  tt.return %newc : tensor<16x16xf32, #Cv2>
}


// Not modified for row-row
// CHECK: tt.func @push_elementwise2
// CHECK: %[[ALOAD:.*]] = tt.load %arg0
// CHECK: %[[AF8E5:.*]] = tt.bitcast %[[ALOAD]]
// CHECK: %[[AF16:.*]] = tt.fp_to_fp %[[AF8E5]]
// CHECK: %[[ACVT:.*]] = triton_gpu.convert_layout %[[AF16]]
// CHECK: %[[C:.*]] = tt.dot %[[ACVT]]
// CHECK: tt.return %[[C]] : tensor<16x16xf32, #mma>
tt.func @push_elementwise2(
                   %pa: tensor<16x16x!tt.ptr<i8>, #ALR> {tt.divisibility=16: i32, tt.contiguity=2 : i32},
                   %pb: tensor<16x16x!tt.ptr<f16>, #BLR> {tt.divisibility=16: i32, tt.contiguity=2 : i32},
                   %c: tensor<16x16xf32, #Cv2>) -> tensor<16x16xf32, #Cv2>{
  %ai8 = tt.load %pa {cache = 1 : i32, evict = 1 : i32, isVolatile = false} : tensor<16x16xi8, #ALR>
  %b = tt.load %pb {cache = 1 : i32, evict = 1 : i32, isVolatile = false} : tensor<16x16xf16, #BLR>
  %af8 = tt.bitcast %ai8: tensor<16x16xi8, #ALR> -> tensor<16x16xf8E5M2, #ALR>
  %a = tt.fp_to_fp %af8: tensor<16x16xf8E5M2, #ALR> -> tensor<16x16xf16, #ALR>
  %dota = triton_gpu.convert_layout %a : (tensor<16x16xf16, #ALR>) -> tensor<16x16xf16, #Av2>
  %dotb = triton_gpu.convert_layout %b : (tensor<16x16xf16, #BLR>) -> tensor<16x16xf16, #Bv2>
  %newc = tt.dot %dota, %dotb, %c {allowTF32 = true, transA = false, transB = false} : tensor<16x16xf16, #Av2> * tensor<16x16xf16, #Bv2> -> tensor<16x16xf32, #Cv2>
  tt.return %newc : tensor<16x16xf32, #Cv2>
}


// Not modified for col-row
// CHECK: tt.func @push_elementwise3
// CHECK: %[[ALOAD:.*]] = tt.load %arg0
// CHECK: %[[AF8E5:.*]] = tt.bitcast %[[ALOAD]]
// CHECK: %[[AF16:.*]] = tt.fp_to_fp %[[AF8E5]]
// CHECK: %[[ACVT:.*]] = triton_gpu.convert_layout %[[AF16]]
// CHECK: %[[C:.*]] = tt.dot %[[ACVT]]
// CHECK: tt.return %[[C]] : tensor<16x16xf32, #mma>
tt.func @push_elementwise3(
                   %pa: tensor<16x16x!tt.ptr<i8>, #ALC> {tt.divisibility=16: i32, tt.contiguity=2 : i32},
                   %pb: tensor<16x16x!tt.ptr<f16>, #BLR> {tt.divisibility=16: i32, tt.contiguity=2 : i32},
                   %c: tensor<16x16xf32, #Cv2>) -> tensor<16x16xf32, #Cv2>{
  %ai8 = tt.load %pa {cache = 1 : i32, evict = 1 : i32, isVolatile = false} : tensor<16x16xi8, #ALC>
  %b = tt.load %pb {cache = 1 : i32, evict = 1 : i32, isVolatile = false} : tensor<16x16xf16, #BLR>
  %af8 = tt.bitcast %ai8: tensor<16x16xi8, #ALC> -> tensor<16x16xf8E5M2, #ALC>
  %a = tt.fp_to_fp %af8: tensor<16x16xf8E5M2, #ALC> -> tensor<16x16xf16, #ALC>
  %dota = triton_gpu.convert_layout %a : (tensor<16x16xf16, #ALC>) -> tensor<16x16xf16, #Av2>
  %dotb = triton_gpu.convert_layout %b : (tensor<16x16xf16, #BLR>) -> tensor<16x16xf16, #Bv2>
  %newc = tt.dot %dota, %dotb, %c {allowTF32 = true, transA = false, transB = false} : tensor<16x16xf16, #Av2> * tensor<16x16xf16, #Bv2> -> tensor<16x16xf32, #Cv2>
  tt.return %newc : tensor<16x16xf32, #Cv2>
}

// Not modified for col-col
// CHECK: tt.func @push_elementwise4
// CHECK: %[[ALOAD:.*]] = tt.load %arg0
// CHECK: %[[AF8E5:.*]] = tt.bitcast %[[ALOAD]]
// CHECK: %[[AF16:.*]] = tt.fp_to_fp %[[AF8E5]]
// CHECK: %[[ACVT:.*]] = triton_gpu.convert_layout %[[AF16]]
// CHECK: %[[C:.*]] = tt.dot %[[ACVT]]
// CHECK: tt.return %[[C]] : tensor<16x16xf32, #mma>
tt.func @push_elementwise4(
                   %pa: tensor<16x16x!tt.ptr<i8>, #ALC> {tt.divisibility=16: i32, tt.contiguity=2 : i32},
                   %pb: tensor<16x16x!tt.ptr<f16>, #BLC> {tt.divisibility=16: i32, tt.contiguity=2 : i32},
                   %c: tensor<16x16xf32, #Cv2>) -> tensor<16x16xf32, #Cv2>{
  %ai8 = tt.load %pa {cache = 1 : i32, evict = 1 : i32, isVolatile = false} : tensor<16x16xi8, #ALC>
  %b = tt.load %pb {cache = 1 : i32, evict = 1 : i32, isVolatile = false} : tensor<16x16xf16, #BLC>
  %af8 = tt.bitcast %ai8: tensor<16x16xi8, #ALC> -> tensor<16x16xf8E5M2, #ALC>
  %a = tt.fp_to_fp %af8: tensor<16x16xf8E5M2, #ALC> -> tensor<16x16xf16, #ALC>
  %dota = triton_gpu.convert_layout %a : (tensor<16x16xf16, #ALC>) -> tensor<16x16xf16, #Av2>
  %dotb = triton_gpu.convert_layout %b : (tensor<16x16xf16, #BLC>) -> tensor<16x16xf16, #Bv2>
  %newc = tt.dot %dota, %dotb, %c {allowTF32 = true, transA = false, transB = false} : tensor<16x16xf16, #Av2> * tensor<16x16xf16, #Bv2> -> tensor<16x16xf32, #Cv2>
  tt.return %newc : tensor<16x16xf32, #Cv2>
}


// Not modified for Volta
// CHECK: tt.func @push_elementwise5
// CHECK: %[[ALOAD:.*]] = tt.load %arg0
// CHECK: %[[AF8E5:.*]] = tt.bitcast %[[ALOAD]]
// CHECK: %[[AF16:.*]] = tt.fp_to_fp %[[AF8E5]]
// CHECK: %[[ACVT:.*]] = triton_gpu.convert_layout %[[AF16]]
// CHECK: %[[C:.*]] = tt.dot %[[ACVT]]
// CHECK: tt.return %[[C]] : tensor<16x16xf32, #mma1>
tt.func @push_elementwise5(
                   %pa: tensor<16x16x!tt.ptr<i8>, #ALR> {tt.divisibility=16: i32, tt.contiguity=2 : i32},
                   %pb: tensor<16x16x!tt.ptr<f16>, #BLC> {tt.divisibility=16: i32, tt.contiguity=2 : i32},
                   %c: tensor<16x16xf32, #Cv1>) -> tensor<16x16xf32, #Cv1>{
  %ai8 = tt.load %pa {cache = 1 : i32, evict = 1 : i32, isVolatile = false} : tensor<16x16xi8, #ALR>
  %b = tt.load %pb {cache = 1 : i32, evict = 1 : i32, isVolatile = false} : tensor<16x16xf16, #BLC>
  %af8 = tt.bitcast %ai8: tensor<16x16xi8, #ALR> -> tensor<16x16xf8E5M2, #ALR>
  %a = tt.fp_to_fp %af8: tensor<16x16xf8E5M2, #ALR> -> tensor<16x16xf16, #ALR>
  %dota = triton_gpu.convert_layout %a : (tensor<16x16xf16, #ALR>) -> tensor<16x16xf16, #Av1>
  %dotb = triton_gpu.convert_layout %b : (tensor<16x16xf16, #BLC>) -> tensor<16x16xf16, #Bv1>
  %newc = tt.dot %dota, %dotb, %c {allowTF32 = true, transA = false, transB = false} : tensor<16x16xf16, #Av1> * tensor<16x16xf16, #Bv1> -> tensor<16x16xf32, #Cv1>
  tt.return %newc : tensor<16x16xf32, #Cv1>
}

// CHECK: tt.func @succeeds_if_arg_is_not_convert_layout
// CHECK: %[[ALOAD:.*]] = tt.load %arg0
// CHECK: %[[ACVT:.*]] = triton_gpu.convert_layout %[[ALOAD]]
// CHECK: %[[AF8E5:.*]] = tt.bitcast %[[ACVT]]
// CHECK: %[[AF16:.*]] = tt.fp_to_fp %[[AF8E5]]
// CHECK: %[[C:.*]] = tt.dot %[[AF16]]
// CHECK: tt.return %[[C]] : tensor<16x16xf32, #mma>
tt.func @succeeds_if_arg_is_not_convert_layout(
                   %pa: tensor<16x16x!tt.ptr<i8>, #ALR> {tt.divisibility=16: i32, tt.contiguity=2 : i32},
                   %pb: tensor<16x16x!tt.ptr<f16>, #BLC> {tt.divisibility=16: i32, tt.contiguity=2 : i32},
                   %c: tensor<16x16xf32, #Cv2>) -> tensor<16x16xf32, #Cv2>{
  %ai8 = tt.load %pa {cache = 1 : i32, evict = 1 : i32, isVolatile = false} : tensor<16x16xi8, #ALR>
  %dotai8 = triton_gpu.convert_layout %ai8 : (tensor<16x16xi8, #ALR>) -> tensor<16x16xi8, #Av2>
  %b = tt.load %pb {cache = 1 : i32, evict = 1 : i32, isVolatile = false} : tensor<16x16xf16, #BLC>
  %dotaf8 = tt.bitcast %dotai8 : tensor<16x16xi8, #Av2> -> tensor<16x16xf8E5M2, #Av2>
  %dota = tt.fp_to_fp %dotaf8 : tensor<16x16xf8E5M2, #Av2> -> tensor<16x16xf16, #Av2>
  %dotb = triton_gpu.convert_layout %b : (tensor<16x16xf16, #BLC>) -> tensor<16x16xf16, #Bv2>
  %newc = tt.dot %dota, %dotb, %c {allowTF32 = true, transA = false, transB = false} : tensor<16x16xf16, #Av2> * tensor<16x16xf16, #Bv2> -> tensor<16x16xf32, #Cv2>
  tt.return %newc : tensor<16x16xf32, #Cv2>
}

}

// -----

#blockedA = #triton_gpu.blocked<{sizePerThread = [1, 2], threadsPerWarp = [4, 8], warpsPerCTA = [4, 1], order = [1, 0]}>
#blockedB = #triton_gpu.blocked<{sizePerThread = [2, 1], threadsPerWarp = [8, 4], warpsPerCTA = [1, 4], order = [0, 1]}>
#mma = #triton_gpu.mma<{versionMajor = 2, versionMinor = 0, warpsPerCTA = [1, 4]}>
module attributes {"triton_gpu.num-warps" = 4 : i32} {

// CHECK: #[[BA:.*]] = #triton_gpu.blocked<{sizePerThread = [1, 2], threadsPerWarp = [4, 8], warpsPerCTA = [4, 1], order = [1, 0]}>
// CHECK: #[[BB:.*]] = #triton_gpu.blocked<{sizePerThread = [2, 1], threadsPerWarp = [8, 4], warpsPerCTA = [1, 4], order = [0, 1]}>
// CHECK: #[[MMA:.*]] = #triton_gpu.mma<{versionMajor = 2, versionMinor = 0, warpsPerCTA = [1, 4]}>

// CHECK: tt.func @push_convert_both_operands
// CHECK: %[[ALOAD:.*]] = tt.load %{{.*}} {cache = 1 : i32, evict = 1 : i32, isVolatile = false} : tensor<16x16xf16, #[[BA]]>
// CHECK: %[[ACVT:.*]] = triton_gpu.convert_layout %[[ALOAD]] : (tensor<16x16xf16, #[[BA]]>) -> tensor<16x16xf16, #triton_gpu.dot_op<{opIdx = 0, parent = #[[MMA]], kWidth = 2}>>
// CHECK: %[[BLOAD:.*]] = tt.load %{{.*}} {cache = 1 : i32, evict = 1 : i32, isVolatile = false} : tensor<16x16xf16, #[[BB]]>
// CHECK: %[[BCVT:.*]] = triton_gpu.convert_layout %[[BLOAD]] : (tensor<16x16xf16, #[[BB]]>) -> tensor<16x16xf16, #triton_gpu.dot_op<{opIdx = 1, parent = #[[MMA]], kWidth = 2}>>
// CHECK: %[[AEXT:.*]] = arith.extf %[[ACVT]] : tensor<16x16xf16, #triton_gpu.dot_op<{opIdx = 0, parent = #[[MMA]], kWidth = 2}>> to tensor<16x16xf32, #triton_gpu.dot_op<{opIdx = 0, parent = #[[MMA]], kWidth = 2}>>
// CHECK: %[[BEXT:.*]] = arith.extf %[[BCVT]] : tensor<16x16xf16, #triton_gpu.dot_op<{opIdx = 1, parent = #[[MMA]], kWidth = 2}>> to tensor<16x16xf32, #triton_gpu.dot_op<{opIdx = 1, parent = #[[MMA]], kWidth = 2}>>
// CHECK: tt.dot %[[AEXT]], %[[BEXT]], %{{.*}} {allowTF32 = true} : tensor<16x16xf32, #triton_gpu.dot_op<{opIdx = 0, parent = #[[MMA]], kWidth = 2}>> * tensor<16x16xf32, #triton_gpu.dot_op<{opIdx = 1, parent = #[[MMA]], kWidth = 2}>> -> tensor<16x16xf32, #mma>
tt.func @push_convert_both_operands(
                   %pa: tensor<16x16x!tt.ptr<f16>, #blockedA> {tt.divisibility=16: i32, tt.contiguity=2 : i32},
                   %pb: tensor<16x16x!tt.ptr<f16>, #blockedB> {tt.divisibility=16: i32, tt.contiguity=2 : i32},
                   %c: tensor<16x16xf32, #mma>) -> tensor<16x16xf32, #mma>{
  %a = tt.load %pa {cache = 1 : i32, evict = 1 : i32, isVolatile = false} : tensor<16x16xf16, #blockedA>
  %b = tt.load %pb {cache = 1 : i32, evict = 1 : i32, isVolatile = false} : tensor<16x16xf16, #blockedB>
  %ae = arith.extf %a : tensor<16x16xf16, #blockedA> to tensor<16x16xf32, #blockedA>
  %be = arith.extf %b : tensor<16x16xf16, #blockedB> to tensor<16x16xf32, #blockedB>
  %al = triton_gpu.convert_layout %ae : (tensor<16x16xf32, #blockedA>) -> tensor<16x16xf32, #triton_gpu.dot_op<{opIdx = 0, parent = #mma, kWidth = 1}>>
  %bl = triton_gpu.convert_layout %be : (tensor<16x16xf32, #blockedB>) -> tensor<16x16xf32, #triton_gpu.dot_op<{opIdx = 1, parent = #mma, kWidth = 1}>>
  %r = tt.dot %al, %bl, %c {allowTF32 = true} : tensor<16x16xf32, #triton_gpu.dot_op<{opIdx = 0, parent = #mma, kWidth = 1}>> * tensor<16x16xf32, #triton_gpu.dot_op<{opIdx = 1, parent = #mma, kWidth = 1}>> -> tensor<16x16xf32, #mma>
  tt.return %r : tensor<16x16xf32, #mma>
}

}
