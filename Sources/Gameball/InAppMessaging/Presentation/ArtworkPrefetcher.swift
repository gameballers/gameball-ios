//
//  ArtworkPrefetcher.swift
//  Gameball
//

import UIKit

/// Loads campaign artwork ahead of time and reports whether a campaign is drawable.
///
/// The whole set is warmed rather than one campaign at a time: an event trigger fires with
/// no warning and no time to fetch, so anything not already in memory would either delay the
/// message or draw a broken frame.
///
/// Readiness is defined as "every URL this campaign needs has a decoded image". A failed load,
/// a load that never happened, and bytes that are not an image all read the same way — not
/// ready — because the only sensible response to all three is to skip the campaign.
final class ArtworkPrefetcher {
    private let session: URLSession
    private let timeout: TimeInterval

    private let queue = DispatchQueue(label: "co.gameball.inappmessaging.artwork")
    private let cache = NSCache<NSURL, UIImage>()
    private var failed: Set<URL> = []

    init(session: URLSession = .shared, timeout: TimeInterval = 5) {
        self.session = session
        self.timeout = timeout
    }

    /// Warms every campaign's artwork concurrently, then calls back exactly once.
    ///
    /// The callback is bounded: a single hung request must not stall the session forever, so
    /// the group wait has a deadline of its own on top of the per-request timeout.
    func warm(campaigns: [InAppMessageCampaign], completion: @escaping () -> Void) {
        var urls: [URL] = []
        var seen: Set<URL> = []
        for campaign in campaigns {
            for url in ArtworkPrefetcher.urls(for: campaign) where !seen.contains(url) {
                seen.insert(url)
                urls.append(url)
            }
        }

        guard !urls.isEmpty else {
            completion()
            return
        }

        let group = DispatchGroup()
        for url in urls {
            group.enter()
            load(url) { group.leave() }
        }

        // A grace period over the per-request timeout, so a protocol that ignores the request
        // timeout still cannot pin the callback.
        let deadline = DispatchTime.now() + timeout + 1
        DispatchQueue.global(qos: .utility).async {
            if group.wait(timeout: deadline) == .timedOut {
                iamLog("artwork warm-up hit its \(Int(self.timeout))s bound; campaigns whose "
                     + "artwork is still missing will be skipped")
            }
            completion()
        }
    }

    func isReady(_ campaign: InAppMessageCampaign) -> Bool {
        let urls = ArtworkPrefetcher.urls(for: campaign)
        // Nothing to load is not the same as nothing loaded: a text-only campaign is always
        // drawable and must never be held back.
        guard !urls.isEmpty else { return true }
        for url in urls where image(for: url) == nil { return false }
        return true
    }

    func image(for url: URL) -> UIImage? {
        return queue.sync { cache.object(forKey: url as NSURL) }
    }

    /// Clears readiness so the next sync re-evaluates. Previously failed URLs are retried —
    /// the failure may have been the network rather than the asset.
    func reset() {
        queue.sync {
            cache.removeAllObjects()
            failed.removeAll()
        }
    }

    // MARK: - Internals

    private static func urls(for campaign: InAppMessageCampaign) -> [URL] {
        return [campaign.message.imageURL, campaign.message.iconURL].compactMap { $0 }
    }

    private func load(_ url: URL, completion: @escaping () -> Void) {
        let alreadyHave = queue.sync { cache.object(forKey: url as NSURL) != nil }
        if alreadyHave {
            completion()
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = timeout

        session.dataTask(with: request) { [weak self] data, _, error in
            guard let self = self else {
                completion()
                return
            }

            if let error = error {
                iamLog("artwork failed to load from \(url): \(error.localizedDescription)")
                self.queue.sync { _ = self.failed.insert(url) }
                completion()
                return
            }

            guard let data = data, let image = UIImage(data: data) else {
                iamLog("artwork at \(url) is not a decodable image")
                self.queue.sync { _ = self.failed.insert(url) }
                completion()
                return
            }

            self.queue.sync {
                self.cache.setObject(image, forKey: url as NSURL)
                self.failed.remove(url)
            }
            completion()
        }.resume()
    }
}
