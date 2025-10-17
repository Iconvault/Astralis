return {
    -- Spritesheet resolution
	packedRes = 1024,
    -- Individual icon resolution
	iconRes = 64,
    -- Color which the icons will have if no color data is available
	defaultColor = "#FFFFFF",
    -- Iconsets to be processed
	iconsets = {
        "material-symbols", -- Google Material Symbols (non-light)
        "ic", -- Google Material Icons
        "tabler", -- Tabler
        "mingcute", -- Mingcute
        "lucide", -- Lucide
        "lucide-lab", -- Lucide Lab
        "uil", -- Unicons
        "uim", -- Unicons Monochrome
    },

	-- Step conditions: Enable/disable specific pipeline steps (usually only needed for debug)
	conditions = {
		fetchIconData = true,
		generateSVG = true,
		convertToPNG = true,
		packSprites = true,
		alphaBleed = true,
		compressImages = true,
		uploadToRoblox = true,
		generateMetadata = true,
	},

    -- List of words which if detected in an icon name will automatically be skipped.
    -- Those are mostly brand names pulled from Tabler, with a notable omission of programming languages and tooling.
    blacklistedWords = {
        "4chan", "airbnb", "airtable", "alipay",
        "amazon", "amigo", "among-us", "android",
        "ao3", "apple", "arc", "asana",
        "astro", "aws", "azure", "badoo",
        "baidu", "bandcamp", "bandlab", "beats",
        "bebo", "behance", "bilibili", "binance",
        "bing", "bitbucket", "blackberry", "blogger",
        "bluesky", "booking", "bumble", "bunpo",
        "cake", "cashapp", "citymapper", "cloudflare",
        "cohost", "coinbase", "comedy-central", "coreos",
        "crunchbase", "ctemplar", "cupra", "databricks",
        "days-counter", "debian", "deezer", "deliveroo",
        "denodo", "deviantart", "digg", "dingtalk",
        "discord", "disney", "disqus", "dolby-digital",
        "douban", "dribbble", "dropbox", "drupal",
        "edge", "electronic-arts", "envato", "etsy",
        "evernote", "facebook", "feedly", "figma",
        "filezilla", "finder", "firefox", "fiverr",
        "flickr", "flightradar24", "flipboard", "fortnite",
        "foursquare", "framer", "funimation", "grammarly",
        "gravatar", "grindr", "guardian", "gumroad",
        "hbo", "hexo", "hipchat", "inertia",
        "instagram", "intercom", "itch", "juejin",
        "kick", "kickstarter", "lastfm", "letterboxd",
        "line", "linkedin", "linktree", "livewire",
        "loom", "mailgun", "mastercard", "mastodon",
        "matrix", "mcdonalds", "medium", "meetup",
        "mercedes", "messenger", "meta", "metabrainz",
        "minecraft", "mixpanel", "monday", "mongodb",
        "mysql", "national-geographic", "netflix", "nextcloud",
        "nord-vpn", "notion", "nytimes", "oauth",
        "office", "ok-ru", "onedrive", "onlyfans",
        "openai", "openvpn", "opera", "pagekit",
        "parsinta", "patreon", "paypal", "paypay",
        "peanut", "pepsi", "picsart", "pinterest",
        "pocket", "printables", "producthunt", "pushbullet",
        "pushover", "qq", "revolut", "rumble",
        "safari", "samsung", "sentry", "sharik",
        "shazam", "shopee", "sketch", "skype",
        "slack", "snapchat", "snapseed", "snowflake",
        "soundcloud", "spacehey", "speedtest", "spotify",
        "stackoverflow", "stackshare", "steam", "stocktwits",
        "storj", "storytel", "strava", "stripe",
        "superhuman", "supernova", "surfshark", "taobao",
        "teams", "ted", "telegram", "tesla",
        "tether", "thingiverse", "threads", "tidal",
        "tiktok", "tinder", "topbuzz", "toyota",
        "trello", "tripadvisor", "tumblr", "twilio",
        "twitch", "twitter", "uber", "unsplash",
        "upwork", "valorant", "vercel", "vimeo",
        "vinted", "visa", "vivaldi", "vk",
        "vlc", "volkswagen", "vsco", "walmart",
        "waze", "wechat", "weibo", "whatsapp",
        "wikipedia", "windows", "windy", "wish",
        "wix", "wordpress", "x", "xbox",
        "xamarin", "xing", "yahoo", "yandex",
        "yarn", "ycombinator", "youtube", "zalando",
        "zapier", "zeit", "zhihu", "zoom",
        "zulip", "zwift"
    }
}