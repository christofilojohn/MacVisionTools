# Acknowledgments and Third-Party Licenses

Mac Vision Tools is built using open-source software and proprietary Apple frameworks. We gratefully acknowledge the following projects and developers.

The overall project is licensed under the Apache License 2.0.

---

## Machine Learning Models & Libraries

### TensorFlow SSD MobileNet V2

Used for Standard Object Detection and the Privacy Guard feature.

* **Project:** [TensorFlow Models](https://github.com/tensorflow/models)
* **Model:** SSD MobileNet V2 320x320 trained on COCO 2017, exported to Core ML with raw detector outputs
* **Copyright:** TensorFlow Authors
* **License:** Apache License 2.0

Licensed under the Apache License, Version 2.0. You may obtain a copy of the License at: http://www.apache.org/licenses/LICENSE-2.0

### EmotiEff (AffectNet Emotion Model)

Used for the "Emotion Vibes" real-time facial emotion recognition feature. specifically using the `mobilenet_7.h5` model architecture and weights.

* **Project:** [EmotiEffLib](https://github.com/sb-ai-lab/EmotiEffLib)
* **Source:** [Sber AI Lab](https://github.com/sb-ai-lab)
* **License:** Apache License 2.0

Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License. You may obtain a copy of the License at: http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions and limitations under the License.

---

## System Frameworks

### Apple Vision Framework

This application utilizes the native Vision framework provided by Apple Inc. for face tracking and other computer vision tasks on macOS.

* **Documentation:** [Apple Developer Documentation - Vision](https://developer.apple.com/documentation/vision)
* **Copyright:** © Apple Inc. All rights reserved.
