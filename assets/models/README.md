# Local Gemma Model Requirement

To run the on-device AI features in QuietNote, you must manually download the Gemma LLM weights. 
These files are **gated by Google** and require you to accept a license agreement, which is why they cannot be downloaded automatically.

## How to download:
1. Go to Kaggle: [Gemma MediaPipe Models](https://www.kaggle.com/models/google/gemma/frameworks/tfLite/)
2. Accept the license agreement on Kaggle if you haven't already.
3. Download the **Gemma 2B IT** (Instruction Tuned) `.bin` file.
4. Rename the downloaded file to `model.bin`.
5. Place the `model.bin` file exactly in this folder (`assets/models/model.bin`).

Once placed, the `FlutterGemmaEngine` in the app will automatically pick it up and initialize the local AI chat session!
