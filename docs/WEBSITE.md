# Plupo website

The public landing page is hosted at https://planetic-labs.github.io/plupo/.

Edit the static files in `website/`. There is no build step, package installation, external font, analytics, or server. All links and illustrations work from the `/plupo/` base path. JavaScript powers an optional illustrated walkthrough and fetches the latest release label; downloads and release links work without it.

To preview locally from the repository root:

```sh
python3 -m http.server 8080 --directory website
```

Open http://localhost:8080. The page adapts to mobile screens, supports keyboard navigation and reduced motion, and does not automatically play the walkthrough.

The **Publish Plupo website** workflow deploys only `website/` on pushes to `main` that change website files or its workflow. It can also be run manually. App builds and releases are separate and are not triggered by website deployment. Pages must use **GitHub Actions** as its publishing source in repository Settings → Pages.

The download button uses GitHub's permanent latest-release asset link for `Plupo-arm64.dmg`. The latest version label comes from GitHub's public release API, with a generic link as a fallback if the request fails or is rate limited. Visitors' browsers contact GitHub for that metadata; the site does not send shelf contents or local file paths.

To add a custom domain later, configure it in repository Settings → Pages, set the domain's DNS records, and update the canonical and social URLs in `website/index.html`. Keep HTTPS enabled.
