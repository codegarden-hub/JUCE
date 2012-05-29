/*
  ==============================================================================

   This file is part of the JUCE library - "Jules' Utility Class Extensions"
   Copyright 2004-11 by Raw Material Software Ltd.

  ------------------------------------------------------------------------------

   JUCE can be redistributed and/or modified under the terms of the GNU General
   Public License (Version 2), as published by the Free Software Foundation.
   A copy of the license is included in the JUCE distribution, or can be found
   online at www.gnu.org/licenses.

   JUCE is distributed in the hope that it will be useful, but WITHOUT ANY
   WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
   A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

  ------------------------------------------------------------------------------

   To release a closed-source product which uses JUCE, commercial licenses are
   available: visit www.rawmaterialsoftware.com/juce for more information.

  ==============================================================================
*/

#if JUCE_MAC

struct DownloadClickDetectorClass  : public ObjCClass <NSObject>
{
    DownloadClickDetectorClass()  : ObjCClass ("JUCEWebClickDetector_")
    {
        addIvar <WebBrowserComponent*> ("owner");

        addMethod (@selector (webView:decidePolicyForNavigationAction:request:frame:decisionListener:),
                   decidePolicyForNavigationAction, "v@:@@@@@");
        addMethod (@selector (webView:didFinishLoadForFrame:), didFinishLoadForFrame, "v@:@@");

        registerClass();
    }

    static void setOwner (id self, WebBrowserComponent* owner)
    {
        object_setInstanceVariable (self, "owner", owner);
    }

private:
    static WebBrowserComponent* getOwner (id self)
    {
        return getIvar<WebBrowserComponent*> (self, "owner");
    }

    static void decidePolicyForNavigationAction (id self, SEL, WebView*, NSDictionary* actionInformation,
                                                 NSURLRequest*, WebFrame*, id <WebPolicyDecisionListener> listener)
    {
        NSURL* url = [actionInformation valueForKey: nsStringLiteral ("WebActionOriginalURLKey")];

        if (getOwner (self)->pageAboutToLoad (nsStringToJuce ([url absoluteString])))
            [listener use];
        else
            [listener ignore];
    }

    static void didFinishLoadForFrame (id self, SEL, WebView* sender, WebFrame* frame)
    {
        if ([frame isEqual: [sender mainFrame]])
        {
            NSURL* url = [[[frame dataSource] request] URL];
            getOwner (self)->pageFinishedLoading (nsStringToJuce ([url absoluteString]));
        }
    }
};

#else

} // (juce namespace)

//==============================================================================
@interface WebViewTapDetector  : NSObject <UIGestureRecognizerDelegate>
{
}

- (BOOL) gestureRecognizer: (UIGestureRecognizer*) gestureRecognizer
         shouldRecognizeSimultaneouslyWithGestureRecognizer: (UIGestureRecognizer*) otherGestureRecognizer;
@end

@implementation WebViewTapDetector

- (BOOL) gestureRecognizer: (UIGestureRecognizer*) gestureRecognizer
         shouldRecognizeSimultaneouslyWithGestureRecognizer: (UIGestureRecognizer*) otherGestureRecognizer
{
    return YES;
}

@end

//==============================================================================
@interface WebViewURLChangeDetector : NSObject <UIWebViewDelegate>
{
    juce::WebBrowserComponent* ownerComponent;
}

- (WebViewURLChangeDetector*) initWithWebBrowserOwner: (juce::WebBrowserComponent*) ownerComponent;
- (BOOL) webView: (UIWebView*) webView shouldStartLoadWithRequest: (NSURLRequest*) request navigationType: (UIWebViewNavigationType) navigationType;
@end

@implementation WebViewURLChangeDetector

- (WebViewURLChangeDetector*) initWithWebBrowserOwner: (juce::WebBrowserComponent*) ownerComponent_
{
    [super init];
    ownerComponent = ownerComponent_;
    return self;
}

- (BOOL) webView: (UIWebView*) webView shouldStartLoadWithRequest: (NSURLRequest*) request navigationType: (UIWebViewNavigationType) navigationType
{
    return ownerComponent->pageAboutToLoad (nsStringToJuce (request.URL.absoluteString));
}
@end

namespace juce {

#endif

//==============================================================================
class WebBrowserComponentInternal
                                   #if JUCE_MAC
                                    : public NSViewComponent
                                   #else
                                    : public UIViewComponent
                                   #endif
{
public:
    WebBrowserComponentInternal (WebBrowserComponent* owner)
    {
       #if JUCE_MAC
        webView = [[WebView alloc] initWithFrame: NSMakeRect (0, 0, 100.0f, 100.0f)
                                       frameName: nsEmptyString()
                                       groupName: nsEmptyString()];
        setView (webView);

        static DownloadClickDetectorClass cls;
        clickListener = [cls.createInstance() init];
        DownloadClickDetectorClass::setOwner (clickListener, owner);
        [webView setPolicyDelegate: clickListener];
        [webView setFrameLoadDelegate: clickListener];
       #else
        webView = [[UIWebView alloc] initWithFrame: CGRectMake (0, 0, 1.0f, 1.0f)];
        setView (webView);

        tapDetector = [[WebViewTapDetector alloc] init];
        urlDetector = [[WebViewURLChangeDetector alloc] initWithWebBrowserOwner: owner];
        gestureRecogniser = nil;
        webView.delegate = urlDetector;
       #endif
    }

    ~WebBrowserComponentInternal()
    {
       #if JUCE_MAC
        [webView setPolicyDelegate: nil];
        [webView setFrameLoadDelegate: nil];
        [clickListener release];
       #else
        webView.delegate = nil;
        [webView removeGestureRecognizer: gestureRecogniser];
        [gestureRecogniser release];
        [tapDetector release];
        [urlDetector release];
       #endif

        setView (nil);
    }

    void goToURL (const String& url,
                  const StringArray* headers,
                  const MemoryBlock* postData)
    {
        NSMutableURLRequest* r
            = [NSMutableURLRequest requestWithURL: [NSURL URLWithString: juceStringToNS (url)]
                                      cachePolicy: NSURLRequestUseProtocolCachePolicy
                                  timeoutInterval: 30.0];

        if (postData != nullptr && postData->getSize() > 0)
        {
            [r setHTTPMethod: nsStringLiteral ("POST")];
            [r setHTTPBody: [NSData dataWithBytes: postData->getData()
                                           length: postData->getSize()]];
        }

        if (headers != nullptr)
        {
            for (int i = 0; i < headers->size(); ++i)
            {
                const String headerName  ((*headers)[i].upToFirstOccurrenceOf (":", false, false).trim());
                const String headerValue ((*headers)[i].fromFirstOccurrenceOf (":", false, false).trim());

                [r setValue: juceStringToNS (headerValue)
                   forHTTPHeaderField: juceStringToNS (headerName)];
            }
        }

        stop();

       #if JUCE_MAC
        [[webView mainFrame] loadRequest: r];
       #else
        [webView loadRequest: r];
       #endif
    }

    void goBack()       { [webView goBack]; }
    void goForward()    { [webView goForward]; }

   #if JUCE_MAC
    void stop()         { [webView stopLoading: nil]; }
    void refresh()      { [webView reload: nil]; }
   #else
    void stop()         { [webView stopLoading]; }
    void refresh()      { [webView reload]; }
   #endif

    void mouseMove (const MouseEvent&)
    {
        // WebKit doesn't capture mouse-moves itself, so it seems the only way to make
        // them work is to push them via this non-public method..
        if ([webView respondsToSelector: @selector (_updateMouseoverWithFakeEvent)])
            [webView performSelector:    @selector (_updateMouseoverWithFakeEvent)];
    }

private:
   #if JUCE_MAC
    WebView* webView;
    NSObject* clickListener;
   #else
    UIWebView* webView;
    WebViewTapDetector* tapDetector;
    WebViewURLChangeDetector* urlDetector;
    UITapGestureRecognizer* gestureRecogniser;
   #endif
};

//==============================================================================
WebBrowserComponent::WebBrowserComponent (const bool unloadPageWhenBrowserIsHidden_)
    : browser (nullptr),
      blankPageShown (false),
      unloadPageWhenBrowserIsHidden (unloadPageWhenBrowserIsHidden_)
{
    setOpaque (true);

    addAndMakeVisible (browser = new WebBrowserComponentInternal (this));
}

WebBrowserComponent::~WebBrowserComponent()
{
    deleteAndZero (browser);
}

//==============================================================================
void WebBrowserComponent::goToURL (const String& url,
                                   const StringArray* headers,
                                   const MemoryBlock* postData)
{
    lastURL = url;

    lastHeaders.clear();
    if (headers != nullptr)
        lastHeaders = *headers;

    lastPostData.setSize (0);
    if (postData != nullptr)
        lastPostData = *postData;

    blankPageShown = false;

    browser->goToURL (url, headers, postData);
}

void WebBrowserComponent::stop()
{
    browser->stop();
}

void WebBrowserComponent::goBack()
{
    lastURL = String::empty;
    blankPageShown = false;
    browser->goBack();
}

void WebBrowserComponent::goForward()
{
    lastURL = String::empty;
    browser->goForward();
}

void WebBrowserComponent::refresh()
{
    browser->refresh();
}

//==============================================================================
void WebBrowserComponent::paint (Graphics&)
{
}

void WebBrowserComponent::checkWindowAssociation()
{
    if (isShowing())
    {
        if (blankPageShown)
            goBack();
    }
    else
    {
        if (unloadPageWhenBrowserIsHidden && ! blankPageShown)
        {
            // when the component becomes invisible, some stuff like flash
            // carries on playing audio, so we need to force it onto a blank
            // page to avoid this, (and send it back when it's made visible again).

            blankPageShown = true;
            browser->goToURL ("about:blank", 0, 0);
        }
    }
}

void WebBrowserComponent::reloadLastURL()
{
    if (lastURL.isNotEmpty())
    {
        goToURL (lastURL, &lastHeaders, &lastPostData);
        lastURL = String::empty;
    }
}

void WebBrowserComponent::parentHierarchyChanged()
{
    checkWindowAssociation();
}

void WebBrowserComponent::resized()
{
    browser->setSize (getWidth(), getHeight());
}

void WebBrowserComponent::visibilityChanged()
{
    checkWindowAssociation();
}

bool WebBrowserComponent::pageAboutToLoad (const String&)  { return true; }
void WebBrowserComponent::pageFinishedLoading (const String&) {}
