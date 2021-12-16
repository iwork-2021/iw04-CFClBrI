/// Copyright (c) 2019 Razeware LLC
///
/// Permission is hereby granted, free of charge, to any person obtaining a copy
/// of this software and associated documentation files (the "Software"), to deal
/// in the Software without restriction, including without limitation the rights
/// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
/// copies of the Software, and to permit persons to whom the Software is
/// furnished to do so, subject to the following conditions:
///
/// The above copyright notice and this permission notice shall be included in
/// all copies or substantial portions of the Software.
///
/// Notwithstanding the foregoing, you may not use, copy, modify, merge, publish,
/// distribute, sublicense, create a derivative work, and/or sell copies of the
/// Software in any work that is designed, intended, or marketed for pedagogical or
/// instructional purposes related to programming, coding, application development,
/// or information technology.  Permission for such use, copying, modification,
/// merger, publication, distribution, sublicensing, creation of derivative works,
/// or sale is expressly withheld.
///
/// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
/// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
/// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
/// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
/// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
/// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
/// THE SOFTWARE.

import UIKit
import Vision

class ViewController: UIViewController {
  
  @IBOutlet var imageView: UIImageView!
  @IBOutlet var cameraButton: UIButton!
  @IBOutlet var photoLibraryButton: UIButton!
  @IBOutlet var resultsView: UIView!
  @IBOutlet var resultsLabel: UILabel!
  @IBOutlet var resultsConstraint: NSLayoutConstraint!
    
    let semphore = DispatchSemaphore(value: ViewController.maxInflightBuffer)
    var inflightBuffer = 0
    static let maxInflightBuffer = 2
    var firstTime = true


    lazy var ImgClassificationRequest: VNCoreMLRequest = {
        do {
            let classifier = try SnacksImageClassifier(configuration: MLModelConfiguration())
            let model = try VNCoreMLModel(for: classifier.model)
            let request = VNCoreMLRequest(model: model, completionHandler: {
                [weak self] request, error in
                self?.processImgObservations(for: request, error: error)
            })
            request.imageCropAndScaleOption = .centerCrop
            return request
        }
        catch {
            fatalError("Failed to create image classification request")
        }
    }()
    
    lazy var healthyClassificationRequest: VNCoreMLRequest = {
        do {
            let classifier = try HealthySnacksClassifier(configuration: MLModelConfiguration())
            let model = try VNCoreMLModel(for: classifier.model)
            let request = VNCoreMLRequest(model: model, completionHandler: {
                [weak self] request, error in
                self?.processHealthyObservations(for: request, error: error)
            })
            request.imageCropAndScaleOption = .centerCrop
            return request
        }
        catch {
            fatalError("Failed to create image classification request")
        }
    }()
    
    func processHealthyObservations(for request: VNRequest, error: Error?) {
        if let results = request.results as? [VNClassificationObservation] {
            if results.isEmpty {
                self.resultsLabel.text! += "nothing found, so I can't tell you whether it is healthy"
            }
            else {
                print(results)
                if results[0].confidence > 0.9 {
                    self.resultsLabel.text! += String(format: "I'm sure it is %@\nwith a credibility of %.1f%%", results[0].identifier, results[0].confidence * 100)
                }
                else {
                    self.resultsLabel.text! += String(format: "maybe it is %@? I'm not sure", results[0].identifier)
                }
            }
        }
        else if let error = error {
            self.resultsLabel.text! += "an error is encountered: \(error.localizedDescription)"
        }
        self.showResultsView()
    }
    
    func processImgObservations(for request: VNRequest, error: Error?) {
        if let results = request.results as? [VNClassificationObservation] {
            if results.isEmpty {
                self.resultsLabel.text = "nothing found, so I can't tell you what it is\n"
            }
            else {
                if results[0].confidence > 0.9 {
                    self.resultsLabel.text = String(format: "I'm sure it is a/an %@\nwith a credibility of %.1f%%\n", results[0].identifier, results[0].confidence * 100)
                }
                else {
                    self.resultsLabel.text = String(format: "maybe it is a/an %@? I'm not sure\n", results[0].identifier)
                }
            }
        }
        else if let error = error {
            self.resultsLabel.text = "an error is encountered: \(error.localizedDescription)\n"
        }
    }
    
    
  override func viewDidLoad() {
    super.viewDidLoad()
    cameraButton.isEnabled = UIImagePickerController.isSourceTypeAvailable(.camera)
    resultsView.alpha = 0
    resultsLabel.text = "choose or take a photo"
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)

    // Show the "choose or take a photo" hint when the app is opened.
    if firstTime {
      showResultsView(delay: 0.5)
      firstTime = false
    }
  }
  
  @IBAction func takePicture() {
    presentPhotoPicker(sourceType: .camera)
  }

  @IBAction func choosePhoto() {
    presentPhotoPicker(sourceType: .photoLibrary)
  }

  func presentPhotoPicker(sourceType: UIImagePickerController.SourceType) {
    let picker = UIImagePickerController()
    picker.delegate = self
    picker.sourceType = sourceType
    present(picker, animated: true)
    hideResultsView()
  }

  func showResultsView(delay: TimeInterval = 0.1) {
    resultsConstraint.constant = 100
    view.layoutIfNeeded()

    UIView.animate(withDuration: 0.5,
                   delay: delay,
                   usingSpringWithDamping: 0.6,
                   initialSpringVelocity: 0.6,
                   options: .beginFromCurrentState,
                   animations: {
      self.resultsView.alpha = 1
      self.resultsConstraint.constant = -10
      self.view.layoutIfNeeded()
    },
    completion: nil)
  }

  func hideResultsView() {
    UIView.animate(withDuration: 0.3) {
      self.resultsView.alpha = 0
    }
  }

    func classify(image: UIImage) {
      let cgImage = image.cgImage!
      DispatchQueue.main.async {
          let handler = VNImageRequestHandler(cgImage: cgImage)
          do {
              try handler.perform([self.ImgClassificationRequest])
              try handler.perform([self.healthyClassificationRequest])
          } catch {
              print("Failed to perform classification: \(error)")
          }
          self.semphore.signal()
      }
  }

}


extension ViewController: VideoCaptureDelegate {
    func videoCapture(capture: VideoCapture, didCaptureVideoFrame sampleBuffer: CMSampleBuffer) {
        self.classify(sampleBuffer: sampleBuffer)
    }
}

extension ViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
  func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
    picker.dismiss(animated: true)

	let image = info[.originalImage] as! UIImage
    imageView.image = image

    classify(image: image)
  }
}

extension ViewController {
    func classify(sampleBuffer: CMSampleBuffer) {
            if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                semphore.wait()
                inflightBuffer += 1
                if inflightBuffer >= ViewController.maxInflightBuffer {
                    inflightBuffer = 0
                }
                DispatchQueue.main.async {
                    let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer)
                    do {
                        try handler.perform([self.ImgClassificationRequest])
                        try handler.perform([self.healthyClassificationRequest])
                    } catch {
                        print("Failed to perform classification: \(error)")
                    }
                    self.semphore.signal()
                }
                
            } else {
                print("Create pixel buffer failed")
            }
        }
}
 
