
/// Protocol used to abstract the information needed to load post related images.
///
@objc protocol PostInformation {

    /// The post is private and hosted on WPcom.
    /// Redundant name due to naming conflict.
    ///
    var isPrivateOnWPCom: Bool { get }

    /// The blog is self-hosted and there is already a basic auth credential stored.
    ///
    var isBlogSelfHostedWithCredentials: Bool { get }
}

/// Class used together with `CachedAnimatedImageView` to facilitate the loading of both
/// still images and animated gifs.
///
@objc class ImageLoader: NSObject {

    private unowned let imageView: CachedAnimatedImageView
    private var successHandler: (() -> Void)?
    private var errorHandler: ((Error?) -> Void)?
    private var placeholder: UIImage?

    @objc init(imageView: CachedAnimatedImageView, gifStrategy: GIFStrategy = .mediumGIFs) {
        self.imageView = imageView
        imageView.gifPlaybackStrategy = gifStrategy.playbackStrategy
        super.init()
    }

    /// Call this in a table/collection cell's `prepareForReuse()`.
    ///
    @objc func prepareForReuse() {
        imageView.prepForReuse()
    }

    @objc(loadImageWithURL:fromPost:andPreferedSize:)
    /// Load an image from a specific post, using the given URL. Supports animated images (gifs) as well.
    ///
    /// - Parameters:
    ///   - url: The URL to load the image from.
    ///   - post: The post where the image is loaded from.
    ///   - size: The prefered size of the image to load.
    ///
    func loadImage(with url: URL, from post: PostInformation, preferedSize size: CGSize = .zero) {
        if url.isGif {
            loadGif(with: url, from: post)
        } else {
            imageView.clean()
            loadStillImage(with: url, from: post, preferedSize: size)
        }
    }

    @objc(loadImageWithURL:fromPost:preferedSize:placeholder:success:error:)
    /// Load an image from a specific post, using the given URL. Supports animated images (gifs) as well.
    ///
    /// - Parameters:
    ///   - url: The URL to load the image from.
    ///   - post: The post where the image is loaded from.
    ///   - size: The prefered size of the image to load.
    ///   - placeholder: A placeholder to show while the image is loading.
    ///   - success: A closure to be called if the image was loaded successfully.
    ///   - error: A closure to be called if there was an error loading the image.
    func loadImage(with url: URL, from post: PostInformation, preferedSize size: CGSize = .zero, placeholder: UIImage?, success: (() -> Void)?, error: ((Error?) -> Void)?) {
        self.placeholder = placeholder
        successHandler = success
        errorHandler = error

        loadImage(with: url, from: post, preferedSize: size)
    }

    // MARK: - Private helpers

    /// Load an animated image from the given URL.
    ///
    private func loadGif(with url: URL, from post: PostInformation) {
        let request: URLRequest
        if post.isPrivateOnWPCom {
            request = PrivateSiteURLProtocol.requestForPrivateSite(from: url)
        } else {
            request = URLRequest(url: url)
        }
        downloadGif(from: request)
    }

    /// Load a static image from the given URL.
    ///
    private func loadStillImage(with url: URL, from post: PostInformation, preferedSize size: CGSize) {
        if url.isFileURL {
            downloadImage(from: url)
        } else if post.isPrivateOnWPCom {
            loadPrivateImage(with: url, from: post, preferedSize: size)
        } else if post.isBlogSelfHostedWithCredentials {
            downloadImage(from: url)
        } else {
            loadProtonUrl(with: url, preferedSize: size)
        }
    }

    /// Loads the image from a private post hosted in WPCom.
    ///
    private func loadPrivateImage(with url: URL, from post: PostInformation, preferedSize size: CGSize) {
        let scale = UIScreen.main.scale
        let scaledSize = CGSize(width: size.width * scale, height: size.height * scale)
        let scaledURL = WPImageURLHelper.imageURLWithSize(scaledSize, forImageURL: url)
        let request = PrivateSiteURLProtocol.requestForPrivateSite(from: scaledURL)

        downloadImage(from: request)
    }

    /// Loads the image from the Proton API with the given size.
    ///
    private func loadProtonUrl(with url: URL, preferedSize size: CGSize) {
        guard let protonURL = PhotonImageURLHelper.photonURL(with: size, forImageURL: url) else {
            downloadImage(from: url)
            return
        }
        downloadImage(from: protonURL)
    }

    /// Download the animated image from the given URL Request.
    ///
    private func downloadGif(from request: URLRequest) {
        imageView.startLoadingAnimation()
        imageView.setAnimatedImage(request, placeholderImage: placeholder, success: { [weak self] in
            self?.imageView.stopLoadingAnimation()
            self?.callSuccessHandler()
        }) { [weak self] (error) in
            self?.imageView.stopLoadingAnimation()
            self?.callErrorHandler(with: error)
        }
    }

    /// Downloads the image from the given URL Request.
    ///
    private func downloadImage(from request: URLRequest) {
        imageView.startLoadingAnimation()
        imageView.setImageWith(request, placeholderImage: placeholder, success: { [weak self] (_, _, image) in
            // Since a success block is specified, we need to set the image manually.
            self?.imageView.image = image
            self?.callSuccessHandler()
        }) { [weak self] (_, _, error) in
            self?.callErrorHandler(with: error)
        }
    }

    /// Downloads the image from the given URL.
    ///
    private func downloadImage(from url: URL) {
        imageView.startLoadingAnimation()
        imageView.downloadImage(from: url, placeholderImage: placeholder, success: { [weak self] (_) in
            self?.callSuccessHandler()
        }) { [weak self] (error) in
            self?.callErrorHandler(with: error)
        }
    }

    private func callSuccessHandler() {
        imageView.stopLoadingAnimation()
        guard successHandler != nil else {
            return
        }
        DispatchQueue.main.async {
            self.successHandler?()
        }
    }

    private func callErrorHandler(with error: Error?) {
        guard let error = error, (error as NSError).code != NSURLErrorCancelled else {
            return
        }
        imageView.stopLoadingAnimation()
        guard errorHandler != nil else {
            return
        }
        DispatchQueue.main.async {
            self.errorHandler?(error)
        }
    }
}
