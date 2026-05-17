//
//  BannerImageCropEditor.swift
//  Communally
//
//  Full-screen pinch + pan crop for profile cover images. `UIImagePickerController`
//  cannot draw a true wide “banner” box; this screen does.
//

import SwiftUI
import UIKit

// MARK: - SwiftUI entry (full screen cover)

struct BannerImageCropFlow: UIViewControllerRepresentable {
    let image: UIImage
    var onSave: (UIImage) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> UINavigationController {
        let root = BannerCropViewController(image: image, onSave: onSave, onCancel: onCancel)
        let nav = UINavigationController(rootViewController: root)
        return nav
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}
}

// MARK: - UIKit

private final class BannerCropViewController: UIViewController, UIScrollViewDelegate {
    private let sourceImage: UIImage
    private let onSave: (UIImage) -> Void
    private let onCancel: () -> Void

    private let scrollView = UIScrollView()
    private let imageView = UIImageView()

    private var hasAppliedInitialLayout = false
    private var lastScrollBounds: CGSize = .zero

    init(image: UIImage, onSave: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
        self.sourceImage = image
        self.onSave = onSave
        self.onCancel = onCancel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        navigationItem.title = "Adjust banner"
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "Cancel",
            style: .plain,
            target: self,
            action: #selector(cancelTapped)
        )
        navigationItem.leftBarButtonItem?.tintColor = CommunallyUIColor.primaryGreen
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Use banner",
            style: .done,
            target: self,
            action: #selector(saveTapped)
        )
        navigationItem.rightBarButtonItem?.tintColor = CommunallyUIColor.primaryGreen

        let hint = UILabel()
        hint.text = "Pinch to zoom — drag to position"
        hint.textColor = UIColor(white: 0.7, alpha: 1)
        hint.font = .systemFont(ofSize: 14, weight: .medium)
        hint.textAlignment = .center
        hint.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hint)

        scrollView.delegate = self
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.decelerationRate = .fast
        scrollView.bounces = true
        scrollView.clipsToBounds = true
        // Match the surrounding view so an early "Save" tap (before layout
        // finishes) can't capture a white frame as the banner.
        scrollView.backgroundColor = .black
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        imageView.contentMode = .scaleAspectFill
        imageView.image = sourceImage
        imageView.clipsToBounds = true
        scrollView.addSubview(imageView)

        // 3.2:1 wide rectangle centered vertically — matches what
        // `communallyAsWideBannerFromCroppedImage` saves and what the profile
        // header renders, so the crop window equals the displayed banner.
        NSLayoutConstraint.activate([
            hint.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            hint.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            hint.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16)
        ])
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            scrollView.heightAnchor.constraint(equalTo: scrollView.widthAnchor, multiplier: 1.0 / 3.2)
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let b = scrollView.bounds.size
        guard b.width > 1, b.height > 1 else { return }
        if !hasAppliedInitialLayout {
            hasAppliedInitialLayout = true
            lastScrollBounds = b
            setupScrollViewForImage()
            updateZoomInsets()
            return
        }
        if abs(b.width - lastScrollBounds.width) > 0.5 || abs(b.height - lastScrollBounds.height) > 0.5 {
            lastScrollBounds = b
            setupScrollViewForImage()
            updateZoomInsets()
        }
    }

    private func setupScrollViewForImage() {
        // Aspect-fill the crop window (scrollView.bounds) with the source image;
        // user can pan and zoom to choose framing.
        let iw = max(sourceImage.size.width, 1)
        let ih = max(sourceImage.size.height, 1)
        let bw = scrollView.bounds.width
        let bh = scrollView.bounds.height

        let s = max(bw / iw, bh / ih)
        let w = iw * s
        let h = ih * s

        scrollView.contentInset = .zero
        imageView.frame = CGRect(x: 0, y: 0, width: w, height: h)
        scrollView.contentSize = imageView.frame.size
        scrollView.maximumZoomScale = 4.0
        scrollView.minimumZoomScale = 1.0
        scrollView.zoomScale = 1.0

        let offX = max(0, (scrollView.contentSize.width - scrollView.bounds.width) * 0.5)
        let offY = max(0, (scrollView.contentSize.height - scrollView.bounds.height) * 0.5)
        scrollView.contentOffset = CGPoint(x: offX, y: offY)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        updateZoomInsets()
    }

    private func updateZoomInsets() {
        let s = imageView.frame.size
        let b = scrollView.bounds.size
        var top: CGFloat = 0, left: CGFloat = 0, bottom: CGFloat = 0, right: CGFloat = 0
        if s.width < b.width { left = (b.width - s.width) * 0.5; right = left }
        if s.height < b.height { top = (b.height - s.height) * 0.5; bottom = top }
        scrollView.contentInset = UIEdgeInsets(top: top, left: left, bottom: bottom, right: right)
    }

    @objc private func cancelTapped() {
        onCancel()
    }

    @objc private func saveTapped() {
        // Guard against an early tap that would render a blank/white frame
        // before the image has been laid out into the scroll view.
        guard hasAppliedInitialLayout,
              imageView.image != nil,
              imageView.frame.width > 1,
              imageView.frame.height > 1 else {
            return
        }
        if let out = renderVisibleImage() {
            onSave(out)
        } else {
            onCancel()
        }
    }

    private func renderVisibleImage() -> UIImage? {
        let size = scrollView.bounds.size
        guard size.width > 0, size.height > 0 else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let img = renderer.image { _ in
            // Captures the exact pixels the user sees (after zoom/scroll + masks).
            scrollView.drawHierarchy(in: scrollView.bounds, afterScreenUpdates: true)
        }
        return downscaleIfNeeded(img, maxPixelWidth: 1400)
    }

    /// Keeps User documents and Firestore payloads reasonable.
    private func downscaleIfNeeded(_ image: UIImage, maxPixelWidth: CGFloat) -> UIImage {
        let pixelW = image.size.width * image.scale
        guard pixelW > maxPixelWidth else { return image }
        let ratio = maxPixelWidth / pixelW
        let newW = image.size.width * ratio
        let newH = image.size.height * ratio
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1.0
        let r = UIGraphicsImageRenderer(size: CGSize(width: newW, height: newH), format: fmt)
        return r.image { _ in
            image.draw(in: CGRect(origin: .zero, size: CGSize(width: newW, height: newH)))
        }
    }
}

// MARK: - Color bridge (no SwiftUI in VC file dependency cycle)

private enum CommunallyUIColor {
    static var primaryGreen: UIColor {
        UIColor(red: 0.18, green: 0.80, blue: 0.44, alpha: 1)
    }
}
