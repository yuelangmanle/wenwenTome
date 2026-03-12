import 'models.dart';

const String defaultWebNovelUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36';

final List<WebNovelSource> builtinBookSources = <WebNovelSource>[
  WebNovelSource(
    id: 'qb520',
    name: 'QB520 \u5168\u672c\u5c0f\u8bf4',
    baseUrl: 'https://www.qb520.cc',
    group: '\u7cbe\u9009\u5185\u7f6e',
    userAgent: defaultWebNovelUserAgent,
    priority: 100,
    search: const BookSourceSearchRule(
      method: HttpMethod.get,
      pathTemplate: '',
      useSearchProviderFallback: true,
    ),
    detail: const BookSourceDetailRule(
      titleRule: SelectorRule(
        expression: 'h1, #info h1, .bookname h1, .info h1',
      ),
      authorRule: SelectorRule(
        expression: '#info, .small, .bookname, .info, body',
        regex: r'\u4f5c\u8005[:\uff1a]\s*([^\n]+)',
      ),
      coverRule: SelectorRule(
        expression: '#fmimg img, .book img, .cover img, img',
        attr: 'src',
        absoluteUrl: true,
      ),
      descriptionRule: SelectorRule(
        expression: '#intro, .intro, .bookintro, #bookintro, .desc',
      ),
      chapterListUrlRule: SelectorRule(
        expression:
            'a[href*="all.html"], a[href*="index.html"], a[href*="catalog"], a[href*="list"]',
        attr: 'href',
        absoluteUrl: true,
      ),
    ),
    chapters: const BookSourceChapterRule(
      itemSelector: '#list a, .listmain a, dd a, #chapterlist a',
      titleRule: SelectorRule(expression: ''),
      urlRule: SelectorRule(expression: '', attr: 'href', absoluteUrl: true),
    ),
    content: const BookSourceContentRule(
      titleRule: SelectorRule(
        expression: 'h1, .content h1, .bookname h1, .headline h1',
      ),
      contentRule: SelectorRule(
        expression:
            '#content, #chaptercontent, #booktxt, .yd_text2, .Readarea, article, .content',
      ),
      nextPageKeyword: '\u4e0b\u4e00\u7ae0',
      removeSelectors: <String>[
        'script',
        'style',
        '.ads',
        '.ad',
        '.banner',
        '.page',
        '.footer',
        '.recommend',
      ],
      decodeQb520Scripts: true,
    ),
    tags: <String>[
      '\u516c\u5f00\u7ad9',
      '\u7ae0\u8282\u7ad9',
      '\u811a\u672c\u89e3\u7801',
    ],
    siteDomains: <String>['qb520.cc'],
  ),
  WebNovelSource(
    id: 'ffmu',
    name: 'FFMU \u5168\u672c\u5c0f\u8bf4',
    baseUrl: 'http://www.ffmu.net',
    group: '\u7cbe\u9009\u5185\u7f6e',
    userAgent: defaultWebNovelUserAgent,
    priority: 95,
    search: const BookSourceSearchRule(
      method: HttpMethod.get,
      pathTemplate: '',
      useSearchProviderFallback: true,
    ),
    detail: const BookSourceDetailRule(
      titleRule: SelectorRule(
        expression: 'h1, #info h1, .bookname h1, .info h1',
      ),
      authorRule: SelectorRule(
        expression: '#info, .small, .bookname, .info, body',
        regex: r'\u4f5c\u8005[:\uff1a]\s*([^\n]+)',
      ),
      coverRule: SelectorRule(
        expression: '#fmimg img, .book img, .cover img, img',
        attr: 'src',
        absoluteUrl: true,
      ),
      descriptionRule: SelectorRule(
        expression: '#intro, .intro, .bookintro, #bookintro, .desc',
      ),
      chapterListUrlRule: SelectorRule(
        expression:
            'a[href*="all.html"], a[href*="index.html"], a[href*="catalog"], a[href*="list"]',
        attr: 'href',
        absoluteUrl: true,
      ),
    ),
    chapters: const BookSourceChapterRule(
      itemSelector: '#list a, .listmain a, dd a, #chapterlist a',
      titleRule: SelectorRule(expression: ''),
      urlRule: SelectorRule(expression: '', attr: 'href', absoluteUrl: true),
    ),
    content: const BookSourceContentRule(
      titleRule: SelectorRule(
        expression: 'h1, .content h1, .bookname h1, .headline h1',
      ),
      contentRule: SelectorRule(
        expression:
            '#content, #chaptercontent, #booktxt, .yd_text2, .Readarea, article, .content',
      ),
      nextPageKeyword: '\u4e0b\u4e00\u7ae0',
      removeSelectors: <String>[
        'script',
        'style',
        '.ads',
        '.ad',
        '.banner',
        '.page',
        '.footer',
        '.recommend',
      ],
    ),
    login: const BookSourceLoginRule(
      loggedInKeyword: '\u9000\u51fa',
      expiredKeyword: '\u767b\u5f55',
      domain: 'ffmu.net',
    ),
    tags: <String>['\u516c\u5f00\u7ad9', '\u7ae0\u8282\u7ad9'],
    siteDomains: <String>['ffmu.net'],
  ),
  WebNovelSource(
    id: 'laoshuwu',
    name: '\u8001\u4e66\u5c4b',
    baseUrl: 'https://www.laoshuwu.com',
    group: '\u7cbe\u9009\u5185\u7f6e',
    userAgent: defaultWebNovelUserAgent,
    priority: 90,
    search: const BookSourceSearchRule(
      method: HttpMethod.get,
      pathTemplate: '',
      useSearchProviderFallback: true,
    ),
    detail: const BookSourceDetailRule(
      titleRule: SelectorRule(
        expression: 'h1, #info h1, .bookname h1, .info h1',
      ),
      authorRule: SelectorRule(
        expression: '#info, .small, .bookname, .info, body',
        regex: r'\u4f5c\u8005[:\uff1a]\s*([^\n]+)',
      ),
      coverRule: SelectorRule(
        expression: '#fmimg img, .book img, .cover img, img',
        attr: 'src',
        absoluteUrl: true,
      ),
      descriptionRule: SelectorRule(
        expression: '#intro, .intro, .bookintro, #bookintro, .desc',
      ),
      chapterListUrlRule: SelectorRule(
        expression:
            'a[href*="all.html"], a[href*="index.html"], a[href*="catalog"], a[href*="list"]',
        attr: 'href',
        absoluteUrl: true,
      ),
    ),
    chapters: const BookSourceChapterRule(
      itemSelector: '#list a, .listmain a, dd a, #chapterlist a',
      titleRule: SelectorRule(expression: ''),
      urlRule: SelectorRule(expression: '', attr: 'href', absoluteUrl: true),
    ),
    content: const BookSourceContentRule(
      titleRule: SelectorRule(
        expression: 'h1, .content h1, .bookname h1, .headline h1',
      ),
      contentRule: SelectorRule(
        expression:
            '#content, #chaptercontent, #booktxt, .yd_text2, .Readarea, article, .content',
      ),
      nextPageKeyword: '\u4e0b\u4e00\u7ae0',
      removeSelectors: <String>[
        'script',
        'style',
        '.ads',
        '.ad',
        '.banner',
        '.page',
        '.footer',
        '.recommend',
      ],
    ),
    tags: <String>['\u516c\u5f00\u7ad9', '\u6d4f\u89c8\u5668\u4f18\u5148'],
    siteDomains: <String>['laoshuwu.com'],
  ),
  WebNovelSource(
    id: 'zigsun',
    name: '\u8ffd\u66f4\u4e66\u5c4b',
    baseUrl: 'https://m.zigsun.com',
    group: '\u7cbe\u9009\u5185\u7f6e',
    userAgent: defaultWebNovelUserAgent,
    priority: 85,
    search: const BookSourceSearchRule(
      method: HttpMethod.get,
      pathTemplate: '',
      useSearchProviderFallback: true,
    ),
    detail: const BookSourceDetailRule(
      titleRule: SelectorRule(
        expression: 'h1, #info h1, .bookname h1, .info h1',
      ),
      authorRule: SelectorRule(
        expression: '#info, .small, .bookname, .info, body',
        regex: r'\u4f5c\u8005[:\uff1a]\s*([^\n]+)',
      ),
      coverRule: SelectorRule(
        expression: '#fmimg img, .book img, .cover img, img',
        attr: 'src',
        absoluteUrl: true,
      ),
      descriptionRule: SelectorRule(
        expression: '#intro, .intro, .bookintro, #bookintro, .desc',
      ),
      chapterListUrlRule: SelectorRule(
        expression:
            'a[href*="all.html"], a[href*="index.html"], a[href*="catalog"], a[href*="list"]',
        attr: 'href',
        absoluteUrl: true,
      ),
    ),
    chapters: const BookSourceChapterRule(
      itemSelector: '#list a, .listmain a, dd a, #chapterlist a',
      titleRule: SelectorRule(expression: ''),
      urlRule: SelectorRule(expression: '', attr: 'href', absoluteUrl: true),
    ),
    content: const BookSourceContentRule(
      titleRule: SelectorRule(
        expression: 'h1, .content h1, .bookname h1, .headline h1',
      ),
      contentRule: SelectorRule(
        expression:
            '#content, #chaptercontent, #booktxt, .yd_text2, .Readarea, article, .content',
      ),
      nextPageKeyword: '\u4e0b\u4e00\u7ae0',
      removeSelectors: <String>[
        'script',
        'style',
        '.ads',
        '.ad',
        '.banner',
        '.page',
        '.footer',
        '.recommend',
      ],
    ),
    tags: <String>['\u516c\u5f00\u7ad9', '\u79fb\u52a8\u7aef'],
    siteDomains: <String>['zigsun.com', 'm.zigsun.com'],
  ),
  WebNovelSource(
    id: 'page254y',
    name: '254\u9875\u4e66\u5e93',
    baseUrl: 'https://wap.254y.com',
    group: '\u7cbe\u9009\u5185\u7f6e',
    userAgent: defaultWebNovelUserAgent,
    priority: 80,
    search: const BookSourceSearchRule(
      method: HttpMethod.get,
      pathTemplate: '',
      useSearchProviderFallback: true,
    ),
    detail: const BookSourceDetailRule(
      titleRule: SelectorRule(
        expression: 'h1, #info h1, .bookname h1, .info h1',
      ),
      authorRule: SelectorRule(
        expression: '#info, .small, .bookname, .info, body',
        regex: r'\u4f5c\u8005[:\uff1a]\s*([^\n]+)',
      ),
      coverRule: SelectorRule(
        expression: '#fmimg img, .book img, .cover img, img',
        attr: 'src',
        absoluteUrl: true,
      ),
      descriptionRule: SelectorRule(
        expression: '#intro, .intro, .bookintro, #bookintro, .desc',
      ),
      chapterListUrlRule: SelectorRule(
        expression:
            'a[href*="all.html"], a[href*="index.html"], a[href*="catalog"], a[href*="list"]',
        attr: 'href',
        absoluteUrl: true,
      ),
    ),
    chapters: const BookSourceChapterRule(
      itemSelector: '#list a, .listmain a, dd a, #chapterlist a',
      titleRule: SelectorRule(expression: ''),
      urlRule: SelectorRule(expression: '', attr: 'href', absoluteUrl: true),
    ),
    content: const BookSourceContentRule(
      titleRule: SelectorRule(
        expression: 'h1, .content h1, .bookname h1, .headline h1',
      ),
      contentRule: SelectorRule(
        expression:
            '#content, #chaptercontent, #booktxt, .yd_text2, .Readarea, article, .content',
      ),
      nextPageKeyword: '\u4e0b\u4e00\u7ae0',
      removeSelectors: <String>[
        'script',
        'style',
        '.ads',
        '.ad',
        '.banner',
        '.page',
        '.footer',
        '.recommend',
      ],
    ),
    tags: <String>['\u516c\u5f00\u7ad9', '\u79fb\u52a8\u517c\u5bb9'],
    siteDomains: <String>['254y.com', 'wap.254y.com'],
  ),
];

final List<WebSearchProvider> builtinSearchProviders = <WebSearchProvider>[
  WebSearchProvider(
    id: 'bing',
    name: 'Bing \u7f51\u9875\u641c\u7d22',
    searchUrlTemplate: 'https://cn.bing.com/search?q={query}',
    resultListSelector: 'li.b_algo',
    resultTitleSelector: 'h2 a',
    resultUrlSelector: 'h2 a@href',
    resultSnippetSelector: '.b_caption p',
    userAgent: defaultWebNovelUserAgent,
    enabled: true,
    priority: 100,
    builtin: true,
  ),
  WebSearchProvider(
    id: 'baidu_mobile',
    name: '\u767e\u5ea6\u79fb\u52a8\u641c\u7d22',
    searchUrlTemplate: 'https://m.baidu.com/s?word={query}',
    resultListSelector: 'div.result, div.c-result, article',
    resultTitleSelector: 'h3 a, .c-title a, a[data-click]',
    resultUrlSelector: 'h3 a@href, .c-title a@href, a[data-click]@href',
    resultSnippetSelector: '.c-line-clamp3, .result-content, .c-span-last',
    userAgent: defaultWebNovelUserAgent,
    enabled: true,
    priority: 90,
    builtin: true,
  ),
  WebSearchProvider(
    id: 'sogou',
    name: '\u641c\u72d7\u7f51\u9875\u641c\u7d22',
    searchUrlTemplate: 'https://www.sogou.com/web?query={query}',
    resultListSelector: '.vrwrap, .rb, .results .vrwrap',
    resultTitleSelector: 'h3 a, .vrTitle a',
    resultUrlSelector: 'h3 a@href, .vrTitle a@href',
    resultSnippetSelector: '.text-layout, .str-info, .ft',
    userAgent: defaultWebNovelUserAgent,
    enabled: true,
    priority: 80,
    builtin: true,
  ),
];
