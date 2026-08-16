# F-Droid Publishing Guide for QuietNote

This repository is configured and ready for F-Droid submission.

## Package Information
- **Application ID:** `io.github.nk2552003.quietnote`
- **Repository:** `https://github.com/NK2552003/QuietNote`
- **License:** `Apache-2.0` (OSI-approved FOSS)
- **Fastlane Metadata:** `fastlane/metadata/android/en-US/`
- **F-Droid Recipe:** `fdroid/io.github.nk2552003.quietnote.yml`

---

## Step-by-Step F-Droid Submission Process

1. **Tag your release in Git:**
   Ensure the commit for release version `1.0.0` has a matching Git tag:
   ```bash
   git tag -a v1.0.0 -m "Release v1.0.0"
   git push origin v1.0.0
   ```

2. **Fork the F-Droid Data Repository on GitLab:**
   Go to [https://gitlab.com/fdroid/fdroiddata](https://gitlab.com/fdroid/fdroiddata) and click **Fork**.

3. **Add the Metadata File:**
   In your forked `fdroiddata` repository, copy the contents of `fdroid/io.github.nk2552003.quietnote.yml` into:
   ```
   metadata/io.github.nk2552003.quietnote.yml
   ```

4. **Open a Merge Request:**
   - Commit the new file to a branch (e.g. `add-quietnote`) in your fork.
   - Open a Merge Request against `fdroid/fdroiddata:master`.
   - Title: `Add io.github.nk2552003.quietnote`
   - Use the default "New App" template in GitLab, check off the verification boxes (100% FOSS, open-source license, no tracking/anti-features).

5. **Automated CI Build & Publication:**
   - The F-Droid GitLab CI pipeline will build `io.github.nk2552003.quietnote` from your tagged source commit.
   - Once merged by F-Droid maintainers, QuietNote will be indexed in the official F-Droid app store catalog and receive automated updates on subsequent `v*` tags.
