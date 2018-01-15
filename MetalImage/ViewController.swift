//
//  ViewController.swift
//  MetalImage
//
//  Created by Geppy Parziale on 1/5/16.
//  Copyright © 2016 iNVASIVECODE Inc. All rights reserved.
//

import UIKit
import Metal
import MetalKit
import MetalPerformanceShaders

class ViewController: UIViewController {

	@IBOutlet var imageView: UIImageView!
	@IBOutlet var pixelSizeSlider: UISlider!

	var pixelSize: UInt = 60
  

	@IBAction func changePixelSize(_ sender: AnyObject) {
		if let slider = sender as? UISlider {
			pixelSize = UInt(slider.value)

			queue.async {

				self.applyFilterMPSCompound()

				let finalResult = self.image(from: self.outTexture)

				DispatchQueue.main.async {
					self.imageView.image = finalResult
				}

			}

		}
	}

	/// The queue to process Metal
	let queue = DispatchQueue(label: "com.invasivecode.metalQueue")

	/// A Metal device
	lazy var device: MTLDevice! = MTLCreateSystemDefaultDevice()

	/// A Metal library
	lazy var defaultLibrary: MTLLibrary! = {
		self.device.newDefaultLibrary()
	}()

	/// A Metal command queue
	lazy var commandQueue: MTLCommandQueue! = {
		NSLog("\(self.device.name!)")
		return self.device.makeCommandQueue()
	}()

	var inTexture: MTLTexture!
	var outTexture: MTLTexture!
  var intermediateTexture: MTLTexture!
	let bytesPerPixel: Int = 4

	/// A Metal compute pipeline state
	var pipelineState: MTLComputePipelineState!

	func setUpMetal() {
    if let kernelFunction = defaultLibrary.makeFunction(name: "pixelate") {
			do {
				pipelineState = try device.makeComputePipelineState(function: kernelFunction)
			}
			catch {
				fatalError("Impossible to setup Metal")
			}
		}
    
	}

	let threadGroupCount = MTLSizeMake(16, 16, 1)

	lazy var threadGroups: MTLSize = {
		MTLSizeMake(Int(self.inTexture.width) / self.threadGroupCount.width, Int(self.inTexture.height) / self.threadGroupCount.height, 1)
	}()


	override func viewDidLoad() {
		super.viewDidLoad()
		queue.async {
			self.setUpMetal()
		}
	}


	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)

		queue.async { () -> Void in

			self.importTexture()

			self.applyFilterMPSCompound()

			let finalResult = self.image(from: self.outTexture)
			DispatchQueue.main.async {
				self.imageView.image = finalResult
			}

		}
	}


	func importTexture() {
		guard let image = UIImage(named: "invasivecode") else {
			fatalError("Can't read image")
		}
		inTexture = texture(from: image)
    
    let imageSize: CGSize = (image.size)
    let intermediateTextureDesciptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: MTLPixelFormat.rgba8Unorm, width: Int(imageSize.width), height: Int(imageSize.height), mipmapped: false)
    
    intermediateTexture = device.makeTexture(descriptor: intermediateTextureDesciptor)
	}


	func applyFilter() {

		let commandBuffer = commandQueue.makeCommandBuffer()
		let commandEncoder = commandBuffer.makeComputeCommandEncoder()

		commandEncoder.setComputePipelineState(pipelineState)
		commandEncoder.setTexture(inTexture, at: 0)
		commandEncoder.setTexture(outTexture, at: 1)

		let buffer = device.makeBuffer(bytes: &pixelSize, length: MemoryLayout<UInt>.size, options: MTLResourceOptions.storageModeShared)
		commandEncoder.setBuffer(buffer, offset: 0, at: 0)

		commandEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupCount)
		commandEncoder.endEncoding()

		commandBuffer.commit()
		commandBuffer.waitUntilCompleted()
	}
  
  func applyFilterMPSCompound() {
    
    let commandBuffer = commandQueue.makeCommandBuffer()
    let blur = MPSImageGaussianBlur(device: device, sigma: Float(pixelSize))
    
    let sobel = MPSImageSobel(device: device)
    
    sobel.encode(commandBuffer: commandBuffer, sourceTexture: inTexture, destinationTexture: intermediateTexture)
    blur.encode(commandBuffer: commandBuffer, sourceTexture: intermediateTexture, destinationTexture: outTexture)
    
    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()

    
  }


	func texture(from image: UIImage) -> MTLTexture {

		guard let cgImage = image.cgImage else {
			fatalError("Can't open image \(image)")
		}

		let textureLoader = MTKTextureLoader(device: self.device)
		do {
			let textureOut = try textureLoader.newTexture(with: cgImage)
			let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: textureOut.pixelFormat, width: textureOut.width, height: textureOut.height, mipmapped: false)
			outTexture = self.device.makeTexture(descriptor: textureDescriptor)
			return textureOut
		}
		catch {
			fatalError("Can't load texture")
		}
	}


	func image(from texture: MTLTexture) -> UIImage {

		let imageByteCount = texture.width * texture.height * bytesPerPixel
		let bytesPerRow = texture.width * bytesPerPixel
		var src = [UInt8](repeating: 0, count: Int(imageByteCount))

		let region = MTLRegionMake2D(0, 0, texture.width, texture.height)
		texture.getBytes(&src, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)

		let bitmapInfo = CGBitmapInfo(rawValue: (CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue))

		let colorSpace = CGColorSpaceCreateDeviceRGB()
		let bitsPerComponent = 8
		let context = CGContext(data: &src,
		                        width: texture.width,
		                        height: texture.height,
		                        bitsPerComponent: bitsPerComponent,
		                        bytesPerRow: bytesPerRow,
		                        space: colorSpace,
		                        bitmapInfo: bitmapInfo.rawValue)

		let dstImageFilter = context?.makeImage()
		
		return UIImage(cgImage: dstImageFilter!, scale: 0.0, orientation: UIImageOrientation.up)
	}
	
}
