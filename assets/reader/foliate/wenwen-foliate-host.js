import './view.js'
import { createTOCView } from './ui/tree.js'
import { createMenu } from './ui/menu.js'

const $ = document.querySelector.bind(document)

const percentFormat = new Intl.NumberFormat('en', { style: 'percent' })
const listFormat = new Intl.ListFormat('en', {
    style: 'short',
    type: 'conjunction',
})

const getCSS = ({ spacing, justify, hyphenate }) => `
    @namespace epub "http://www.idpf.org/2007/ops";
    html { color-scheme: light dark; }
    @media (prefers-color-scheme: dark) {
        a:link { color: lightblue; }
    }
    p, li, blockquote, dd {
        line-height: ${spacing};
        text-align: ${justify ? 'justify' : 'start'};
        -webkit-hyphens: ${hyphenate ? 'auto' : 'manual'};
        hyphens: ${hyphenate ? 'auto' : 'manual'};
        -webkit-hyphenate-limit-before: 3;
        -webkit-hyphenate-limit-after: 2;
        -webkit-hyphenate-limit-lines: 2;
        hanging-punctuation: allow-end last;
        widows: 2;
    }
    [align="left"] { text-align: left; }
    [align="right"] { text-align: right; }
    [align="center"] { text-align: center; }
    [align="justify"] { text-align: justify; }
    pre { white-space: pre-wrap !important; }
    aside[epub|type~="endnote"],
    aside[epub|type~="footnote"],
    aside[epub|type~="note"],
    aside[epub|type~="rearnote"] {
        display: none;
    }
`

const formatLanguageMap = value => {
    if (!value) return ''
    if (typeof value === 'string') return value
    const keys = Object.keys(value)
    return keys.length ? value[keys[0]] : ''
}

const formatOneContributor = contributor =>
    typeof contributor === 'string'
        ? contributor
        : formatLanguageMap(contributor?.name)

const formatContributor = contributor =>
    Array.isArray(contributor)
        ? listFormat.format(contributor.map(formatOneContributor))
        : formatOneContributor(contributor)

const normalizeText = text =>
    String(text ?? '')
        .replace(/\r\n/g, '\n')
        .replace(/\r/g, '\n')

const createSectionsFromText = (text, sections) => {
    if (Array.isArray(sections) && sections.length) {
        return sections.map((section, index) => ({
            id: section.id ?? `section-${index}`,
            title: section.title ?? `Section ${index + 1}`,
            content: normalizeText(section.content ?? ''),
        }))
    }
    return [{ id: 'full-text', title: 'Full text', content: normalizeText(text) }]
}

const callFlutterHandler = async payload => {
    const controller = globalThis.flutter_inappwebview
    if (controller?.callHandler) {
        try {
            await controller.callHandler('foliateHost', payload)
            return
        } catch (error) {
            console.warn('foliateHost handler failed', error)
        }
    }
    console.info('foliateHost', payload)
}

class WenwenReaderHost {
    constructor() {
        this.mode = 'idle'
        this.view = null
        this.textSections = []
        this.textTocView = null
        this.style = {
            spacing: 1.4,
            justify: true,
            hyphenate: true,
        }
        this._bindUi()
        this.notify('ready', {
            capabilities: ['epub', 'txt'],
            mode: this.mode,
        })
    }

    _bindUi() {
        $('#side-bar-button').addEventListener('click', () => {
            $('#dimming-overlay').classList.add('show')
            $('#side-bar').classList.add('show')
        })
        $('#dimming-overlay').addEventListener('click', () => this.closeSideBar())

        const menu = createMenu([
            {
                name: 'layout',
                label: 'Layout',
                type: 'radio',
                items: [
                    ['Paginated', 'paginated'],
                    ['Scrolled', 'scrolled'],
                ],
                onclick: value => {
                    if (this.mode === 'epub') {
                        this.view?.renderer?.setAttribute('flow', value)
                    }
                },
            },
        ])
        menu.element.classList.add('menu')
        $('#menu-button').append(menu.element)
        $('#menu-button > button').addEventListener('click', () =>
            menu.element.classList.toggle('show'))
        menu.groups.layout.select('paginated')

        $('#left-button').addEventListener('click', () => this.goLeft())
        $('#right-button').addEventListener('click', () => this.goRight())
        $('#progress-slider').addEventListener('input', event => {
            const value = parseFloat(event.target.value)
            if (this.mode === 'epub') {
                this.view?.goToFraction(value)
            } else if (this.mode === 'text') {
                this.goToTextFraction(value)
            }
        })
        $('#file-input').addEventListener('change', event => {
            const [file] = event.target.files ?? []
            if (!file) return
            const lowerName = file.name.toLowerCase()
            if (lowerName.endsWith('.txt')) {
                file.text().then(text =>
                    this.openText({
                        title: file.name,
                        text,
                    }))
            } else {
                this.openEpubFile(file)
            }
        })
        $('#file-button').addEventListener('click', () => $('#file-input').click())
        $('#text-reader').addEventListener('scroll', () => this._syncTextProgress())
        document.addEventListener('keydown', event => this._handleKeydown(event))
    }

    closeSideBar() {
        $('#dimming-overlay').classList.remove('show')
        $('#side-bar').classList.remove('show')
    }

    notify(type, detail = {}) {
        void callFlutterHandler({
            type,
            detail,
        })
    }

    _handleKeydown(event) {
        if (event.key === 'ArrowLeft' || event.key === 'h') this.goLeft()
        if (event.key === 'ArrowRight' || event.key === 'l') this.goRight()
    }

    _setShellVisible(visible) {
        $('#header-bar').style.visibility = visible ? 'visible' : 'hidden'
        $('#nav-bar').style.visibility = visible ? 'visible' : 'hidden'
        $('#progress-slider').style.visibility = visible ? 'visible' : 'hidden'
    }

    _resetReaderSurface() {
        this.closeSideBar()
        this.view?.remove()
        this.view = null
        this.textSections = []
        this.textTocView = null
        $('#drop-target').style.visibility = 'hidden'
        $('#text-reader').classList.remove('show')
        $('#text-content').replaceChildren()
        $('#toc-view').replaceChildren()
        $('#tick-marks').replaceChildren()
        $('#side-bar-cover').removeAttribute('src')
    }

    _setSidebarMetadata({ title = '', author = '' }) {
        document.title = title || 'Wenwen Tome'
        $('#side-bar-title').innerText = title
        $('#side-bar-author').innerText = author
    }

    async openEpubFile(file) {
        this._resetReaderSurface()
        this.mode = 'epub'
        this.view = document.createElement('foliate-view')
        document.body.append(this.view)
        await this.view.open(file)
        this._wireEpubView()
        this.notify('opened', {
            mode: this.mode,
            fileName: file.name,
        })
    }

    async openEpubUrl(url) {
        this._resetReaderSurface()
        this.mode = 'epub'
        this.view = document.createElement('foliate-view')
        document.body.append(this.view)
        await this.view.open(url)
        this._wireEpubView()
        this.notify('opened', {
            mode: this.mode,
            url,
        })
    }

    _wireEpubView() {
        this.view.addEventListener('load', event => {
            event.detail.doc.addEventListener('keydown', keyboardEvent =>
                this._handleKeydown(keyboardEvent))
        })
        this.view.addEventListener('relocate', event => this._onEpubRelocate(event.detail))
        this.view.renderer.setStyles?.(getCSS(this.style))
        this.view.renderer.next()

        const { book } = this.view
        this._setShellVisible(true)
        this._setSidebarMetadata({
            title: formatLanguageMap(book.metadata?.title) || 'Untitled Book',
            author: formatContributor(book.metadata?.author),
        })

        Promise.resolve(book.getCover?.())?.then(blob => {
            if (blob) $('#side-bar-cover').src = URL.createObjectURL(blob)
        })

        const toc = book.toc
        if (toc) {
            const tocView = createTOCView(toc, href => {
                this.view.goTo(href).catch(error => console.error(error))
                this.closeSideBar()
            })
            $('#toc-view').replaceChildren(tocView.element)
            this.textTocView = tocView
        }

        const slider = $('#progress-slider')
        slider.dir = book.dir
        slider.value = 0
        for (const fraction of this.view.getSectionFractions()) {
            const option = document.createElement('option')
            option.value = fraction
            $('#tick-marks').append(option)
        }
    }

    _onEpubRelocate(detail) {
        const { fraction, location, tocItem, pageItem } = detail
        const percent = percentFormat.format(fraction)
        const label = pageItem ? `Page ${pageItem.label}` : `Loc ${location.current}`
        const slider = $('#progress-slider')
        slider.value = fraction
        slider.title = `${percent} ${label}`
        this.textTocView?.setCurrentHref?.(tocItem?.href ?? '')
        this.notify('relocate', {
            mode: this.mode,
            fraction,
            location: location.current,
            tocHref: tocItem?.href ?? null,
        })
    }

    openText(payload) {
        this._resetReaderSurface()
        this.mode = 'text'
        this._setShellVisible(true)
        const sections = createSectionsFromText(payload?.text ?? '', payload?.sections)
        this.textSections = sections
        this._setSidebarMetadata({
            title: payload?.title ?? 'Untitled Text',
            author: payload?.author ?? '',
        })

        const article = $('#text-content')
        article.replaceChildren()
        const heading = document.createElement('h1')
        heading.innerText = payload?.title ?? 'Untitled Text'
        article.append(heading)
        if (payload?.author) {
            const author = document.createElement('div')
            author.className = 'author'
            author.innerText = payload.author
            article.append(author)
        }

        for (const section of sections) {
            const element = document.createElement('section')
            element.id = section.id
            const title = document.createElement('h2')
            title.innerText = section.title
            const paragraph = document.createElement('div')
            paragraph.innerText = section.content
            element.append(title, paragraph)
            article.append(element)
        }

        $('#text-reader').classList.add('show')
        this._renderTextToc(sections)
        this._syncTextProgress()
        this.notify('opened', {
            mode: this.mode,
            sections: sections.length,
        })
    }

    _renderTextToc(sections) {
        const root = document.createElement('ol')
        for (const section of sections) {
            const item = document.createElement('li')
            const link = document.createElement('a')
            link.href = `#${section.id}`
            link.innerText = section.title
            link.addEventListener('click', event => {
                event.preventDefault()
                document.getElementById(section.id)?.scrollIntoView({
                    behavior: 'smooth',
                    block: 'start',
                })
                this.closeSideBar()
            })
            item.append(link)
            root.append(item)
        }
        $('#toc-view').replaceChildren(root)
    }

    _syncTextProgress() {
        if (this.mode !== 'text') return
        const container = $('#text-reader')
        const maxScroll = Math.max(container.scrollHeight - container.clientHeight, 1)
        const fraction = Math.max(0, Math.min(1, container.scrollTop / maxScroll))
        const slider = $('#progress-slider')
        slider.value = fraction
        slider.title = percentFormat.format(fraction)
        this.notify('relocate', {
            mode: this.mode,
            fraction,
        })
    }

    goLeft() {
        if (this.mode === 'epub') {
            this.view?.goLeft()
            return
        }
        if (this.mode === 'text') {
            const container = $('#text-reader')
            container.scrollBy({ top: -container.clientHeight * 0.9, behavior: 'smooth' })
        }
    }

    goRight() {
        if (this.mode === 'epub') {
            this.view?.goRight()
            return
        }
        if (this.mode === 'text') {
            const container = $('#text-reader')
            container.scrollBy({ top: container.clientHeight * 0.9, behavior: 'smooth' })
        }
    }

    goToTextFraction(fraction) {
        if (this.mode !== 'text') return
        const container = $('#text-reader')
        const maxScroll = Math.max(container.scrollHeight - container.clientHeight, 1)
        container.scrollTo({
            top: maxScroll * fraction,
            behavior: 'auto',
        })
    }
}

const host = new WenwenReaderHost()
globalThis.WenwenReaderHost = {
    openEpubFile: file => host.openEpubFile(file),
    openEpubUrl: url => host.openEpubUrl(url),
    openText: payload => host.openText(payload),
    getMode: () => host.mode,
}

const params = new URLSearchParams(location.search)
const url = params.get('url')
if (url) {
    host.openEpubUrl(url).catch(error => console.error(error))
} else {
    $('#drop-target').style.visibility = 'visible'
}
