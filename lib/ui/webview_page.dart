import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// 应用内浏览器：直接在当前 APP 的 WebView 中打开公告原文，
/// 避免每次都跳转到系统/手机浏览器。支持前进/后退/刷新/用外部浏览器打开。
class WebviewPage extends StatefulWidget {
  final String url;
  final String? title;
  const WebviewPage({super.key, required this.url, this.title});

  @override
  State<WebviewPage> createState() => _WebviewPageState();
}

class _WebviewPageState extends State<WebviewPage> {
  late final WebViewController _controller;
  bool _loading = true;
  bool _canGoBack = false;
  bool _canGoForward = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() => _loading = true),
          onPageFinished: (_) async {
            setState(() => _loading = false);
            _canGoBack = await _controller.canGoBack();
            _canGoForward = await _controller.canGoForward();
            if (mounted) setState(() {});
          },
          onWebResourceError: (_) {},
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  Future<void> _openExternal() async {
    try {
      await launchUrl(
        Uri.parse(widget.url),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final night = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title ?? '公告详情'),
        bottom: _loading
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
        actions: [
          IconButton(
            tooltip: '后退',
            icon: const Icon(Icons.arrow_back),
            onPressed: _canGoBack
                ? () async {
                    await _controller.goBack();
                    if (mounted) setState(() {});
                  }
                : null,
          ),
          IconButton(
            tooltip: '前进',
            icon: const Icon(Icons.arrow_forward),
            onPressed: _canGoForward
                ? () async {
                    await _controller.goForward();
                    if (mounted) setState(() {});
                  }
                : null,
          ),
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: () => _controller.reload(),
          ),
          IconButton(
            tooltip: '用浏览器打开',
            icon: const Icon(Icons.open_in_browser),
            onPressed: _openExternal,
          ),
        ],
      ),
      body: WebViewWidget(controller: _controller),
      // 夜间模式下 WebView 内容本身由站点控制，这里仅保证背景统一
      backgroundColor: night ? const Color(0xFF0B0E14) : Colors.white,
    );
  }
}
