// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get commonCancel => '取消';

  @override
  String get commonDelete => '删除';

  @override
  String get commonEdit => '编辑';

  @override
  String get commonSave => '保存';

  @override
  String get commonClose => '关闭';

  @override
  String get commonBack => '返回';

  @override
  String get commonHelp => '帮助';

  @override
  String get commonCreate => '创建';

  @override
  String get commonRename => '重命名';

  @override
  String get commonConfirm => '确认';

  @override
  String get commonSet => '设置';

  @override
  String get commonNone => '无';

  @override
  String get commonExport => '导出';

  @override
  String get commonOverwrite => '覆盖';

  @override
  String get commonSaveChanges => '保存更改';

  @override
  String get commonNameRequired => '名称不能为空';

  @override
  String get commonDuplicate => '复制';

  @override
  String get commonDiscard => '放弃';

  @override
  String get commonAddFavorite => '加入收藏';

  @override
  String get commonRemoveFavorite => '取消收藏';

  @override
  String get commonRetry => '重试';

  @override
  String get commonLoading => '加载中';

  @override
  String get commonUnsavedTitle => '未保存的修改';

  @override
  String get commonUnsavedMessage => '有尚未保存的修改，继续之前要保存吗？';

  @override
  String get mainGallery => '图库';

  @override
  String get mainResultsGrid => '网格';

  @override
  String get mainResultsViewer => '看图';

  @override
  String get mainResultGenerating => '生成中';

  @override
  String get mainResultPending => '排队中';

  @override
  String get mainServerHistory => '历史';

  @override
  String get mainTools => '工具';

  @override
  String get mainSave => '保存';

  @override
  String get mainExport => '导出';

  @override
  String get mainEdit => '编辑';

  @override
  String get mainEnterPrompt => '输入提示词';

  @override
  String get mainMoreActions => '更多操作';

  @override
  String get mainHelp => '帮助';

  @override
  String get mainAuthError => '认证错误：请检查 API 设置';

  @override
  String get mainSettings => '设置';

  @override
  String mainImportFailed(String error) {
    return '导入设置失败：$error';
  }

  @override
  String get mainSavePreset => '保存预设';

  @override
  String get mainPresetName => '预设名称';

  @override
  String get generationSheetPrompt => '提示词';

  @override
  String get generationSheetInputs => '图片输入';

  @override
  String get generationSheetParameters => '参数';

  @override
  String get mainExitConfirmation => '确定要退出吗？';

  @override
  String get settingsApiSettings => 'API 设置';

  @override
  String get settingsGeneralSettings => '通用设置';

  @override
  String get settingsUiSettings => '界面设置';

  @override
  String get settingsExport => '导出';

  @override
  String get settingsSecurity => '安全';

  @override
  String get settingsDemoMode => '演示模式';

  @override
  String get settingsLinks => '链接';

  @override
  String get settingsLanguage => '语言';

  @override
  String get settingsApiKeyLabel => 'NovelAI API Key';

  @override
  String get settingsApiKeyHint => 'pst-xxxx...';

  @override
  String get settingsApiKeyVisibility => '显示或隐藏 API 密钥';

  @override
  String get settingsApiManaged => 'NovelAI API Key 由后端托管';

  @override
  String get settingsApiManagedDesc =>
      '此 Web 服务使用后端保存的 NovelAI token。浏览器不会保存或发送 NovelAI token。';

  @override
  String get gatewayLogout => '退出登录';

  @override
  String get gatewayQueueStatus => '队列状态';

  @override
  String get gatewayQueueIdle => '空闲';

  @override
  String get gatewayQueueQueued => '排队';

  @override
  String get gatewayQueueActive => '生成中';

  @override
  String get gatewayQuotaFreeLabel => '免费额度';

  @override
  String get gatewayQuotaPaidLabel => '付费点数';

  @override
  String get gatewayQuotaUnlimited => '无限';

  @override
  String get gatewayQuotaRefresh => '点击刷新自己的额度';

  @override
  String get gatewayErrNotAuthenticated => '登录已失效，请重新登录。';

  @override
  String get gatewayErrAuthUnavailable => '登录服务暂时不可用，请稍后重试。';

  @override
  String get gatewayErrLoginFailed => '登录未能通过验证，请重试。';

  @override
  String get gatewayErrAccountNotLinked => '该登录身份未关联本站账号，或账号已被停用。';

  @override
  String get gatewayErrPermissionDenied => '当前账号没有执行此操作的权限。';

  @override
  String get gatewayErrInvalidParameters => '请求参数无效，请检查尺寸、步数或采样器。';

  @override
  String get gatewayErrPointsInsufficient => '可用点数不足，无法完成本次请求。';

  @override
  String get gatewayErrQuoteChanged => '价格已变化，请确认新价格后重试。';

  @override
  String get gatewayErrFreeAllowanceExhausted => '免费额度暂时用尽，本次请求需要消耗付费点数。';

  @override
  String get gatewayErrQueueFull => '当前未完成的任务已达上限，请等待部分任务完成后再提交。';

  @override
  String get gatewayErrDuplicateRequest => '该请求编号已被用于不同内容的请求。';

  @override
  String get gatewayErrRequestTooLarge => '请求内容过大。';

  @override
  String get gatewayErrUpstream => 'NovelAI 未能完成请求，请稍后重试。';

  @override
  String get gatewayErrInterrupted => '任务因服务重启而中断，没有扣费，可以重试。';

  @override
  String get gatewayErrNotFound => '未找到请求的内容。';

  @override
  String get gatewayErrTaskActive => '该项目仍在排队或生成中。';

  @override
  String get gatewayErrDuplicateGeneration => '参数没有变化，请检查 Seed。';

  @override
  String get gatewayErrRateLimited => '请求过于频繁，请稍候再试。';

  @override
  String get gatewayErrServiceUnavailable => '服务暂时不可用，请稍后重试。';

  @override
  String get gatewayErrInternal => '服务器出现内部错误，请稍后重试。';

  @override
  String get gatewayErrNetwork => '网络错误，请检查网络后重试。';

  @override
  String get gatewayErrTimeout => '请求超时，请重试。';

  @override
  String get gatewayErrUnknown => '请求失败，请稍后重试。';

  @override
  String get gatewayErrDirectAnlas => 'NovelAI 账号的 Anlas 不足，无法完成本次请求。';

  @override
  String get gatewayErrDirectRateLimited => 'NovelAI 正在限制请求频率，请稍候再试。';

  @override
  String get gatewayErrDirectForbidden => 'NovelAI 拒绝了当前账号的此次请求。';

  @override
  String get toolErrApiKeyRejected => 'NovelAI 拒绝了该 API 密钥，请在设置中检查。';

  @override
  String get gatewaySessionExpiredTitle => '登录已失效';

  @override
  String get gatewaySessionExpiredBody => '你的登录已结束。请重新登录后继续；在此之前本页内容不会丢失。';

  @override
  String get gatewaySessionExpiredConfirm => '重新登录';

  @override
  String get gatewayAuthContinue => '通过 only WebAuth 继续';

  @override
  String get gatewayAuthRetry => '重试';

  @override
  String get gatewayLoginOpenFailed => '无法打开认证页面，请刷新后重试。';

  @override
  String get gatewayLogoutFailed => '退出登录失败，你仍处于登录状态，请重试。';

  @override
  String get settingsAutoSave => '自动保存图片';

  @override
  String get settingsAutoSaveDesc => '自动将所有生成的图片保存到输出文件夹';

  @override
  String get settingsSmartStyleImport => '智能风格导入';

  @override
  String get settingsSmartStyleImportDesc => '从导入的提示词中移除风格标签并恢复风格选择';

  @override
  String get settingsCharInsertTarget => '将保存的角色添加到编辑器';

  @override
  String get settingsCharInsertTargetDesc =>
      '在提示词框中选择保存的角色时，将添加角色卡片，而不是把标签插入主提示词';

  @override
  String get settingsRememberSession => '记住会话';

  @override
  String get settingsRememberSessionDesc => '自动保存提示词、设置和参考图，用于崩溃恢复';

  @override
  String get settingsImg2ImgImportPrompt => '图生图导入提示词';

  @override
  String get settingsImg2ImgImportPromptDesc => '选择带元数据的原图时自动填充图生图提示词';

  @override
  String get settingsSaveToAlbum => '保存到相册';

  @override
  String get settingsSaveToAlbumDesc => '自动将新生成的内容添加到此相册';

  @override
  String get settingsEditButton => '编辑按钮';

  @override
  String get settingsEditButtonDesc => '在图片查看器中显示编辑/重绘按钮';

  @override
  String get settingsDirectorRefShelf => '导演参考';

  @override
  String get settingsDirectorRefShelfDesc => '在高级选项中显示导演参考控件';

  @override
  String get settingsVibeTransferShelf => '氛围迁移';

  @override
  String get settingsVibeTransferShelfDesc => '在高级选项中显示氛围迁移控件';

  @override
  String get settingsCharEditorMode => '角色编辑模式';

  @override
  String get settingsCharEditorModeDesc => '在设置面板使用展开式角色编辑器，而非紧凑栏';

  @override
  String get settingsThemeBuilder => '主题编辑器';

  @override
  String get settingsStripMetadata => '导出时移除元数据';

  @override
  String get settingsStripMetadataDesc => '从导出图片中移除生成信息（提示词、设置）';

  @override
  String get settingsPinLock => 'PIN 锁';

  @override
  String get settingsPinLockDesc => '打开应用需输入 4–8 位 PIN 码';

  @override
  String get settingsLockOnResume => '恢复时锁定';

  @override
  String get settingsLockOnResumeDesc => '从后台返回时重新锁定应用';

  @override
  String get settingsBiometricUnlock => '生物识别解锁';

  @override
  String get settingsBiometricUnlockDesc => '使用指纹或面容解锁';

  @override
  String get settingsBiometricsUnavailable => '此设备不支持生物识别';

  @override
  String get settingsSetPin => '设置 PIN';

  @override
  String get settingsPinDigitsHint => '4–8 位数字';

  @override
  String get settingsPinMustBeDigits => 'PIN 必须是 4–8 位数字';

  @override
  String get settingsPinsDoNotMatch => 'PIN 不一致';

  @override
  String get settingsEnterCurrentPin => '输入当前 PIN';

  @override
  String get settingsEnterPinHint => '输入 PIN';

  @override
  String get settingsIncorrectPin => 'PIN 错误';

  @override
  String get settingsDemoModeDesc => '图库中仅显示演示安全图片';

  @override
  String get settingsSelectDemoImages => '选择演示图片';

  @override
  String get settingsTagSuggestionsHidden => '演示模式开启时标签建议已隐藏';

  @override
  String get settingsPositivePrefix => '正向前缀';

  @override
  String get settingsNegativePrefix => '负向前缀';

  @override
  String get settingsEditPositivePrefix => '编辑正向前缀';

  @override
  String get settingsDemoPrefixes => '演示前缀';

  @override
  String get settingsGithubRepository => 'GitHub 仓库';

  @override
  String get galleryTitle => '图库';

  @override
  String get galleryDemoTitle => '图库（演示）';

  @override
  String get gallerySearchTags => '搜索标签…';

  @override
  String gallerySelectedCount(int count) {
    return '已选择 $count 项';
  }

  @override
  String get galleryDeselectAll => '取消全选';

  @override
  String get gallerySelectAll => '全选';

  @override
  String get galleryFavoritesFilter => '收藏筛选';

  @override
  String get gallerySort => '排序';

  @override
  String get gallerySelectMode => '选择模式';

  @override
  String galleryColumnsCount(int count) {
    return '$count 列';
  }

  @override
  String get gallerySortDateNewest => '日期（最新）';

  @override
  String get gallerySortDateOldest => '日期（最早）';

  @override
  String get gallerySortNameAZ => '名称（A-Z）';

  @override
  String get gallerySortNameZA => '名称（Z-A）';

  @override
  String get gallerySortSizeLargest => '大小（最大）';

  @override
  String get gallerySortSizeSmallest => '大小（最小）';

  @override
  String get gallerySortDateAddedNewest => '添加时间（最新）';

  @override
  String get gallerySortDateAddedOldest => '添加时间（最早）';

  @override
  String get galleryNoDemoImages => '未选择演示图片';

  @override
  String get galleryNoFavorites => '无收藏';

  @override
  String get galleryNoImagesInAlbum => '相册内无图片';

  @override
  String get galleryNoImagesFound => '未找到图片';

  @override
  String get galleryAll => '全部';

  @override
  String galleryCopiedCount(int count) {
    return '已复制 $count 项';
  }

  @override
  String galleryImagesCopiedCount(int count) {
    return '已复制 $count 张图片';
  }

  @override
  String galleryPasteInto(String name) {
    return '粘贴到 $name';
  }

  @override
  String galleryPastedIntoAlbum(int count, String name) {
    return '已将 $count 张图片粘贴到 $name';
  }

  @override
  String get galleryClearClipboard => '清空剪贴板';

  @override
  String get galleryNewAlbum => '新建相册';

  @override
  String get galleryAlbumName => '相册名称';

  @override
  String get galleryRenameAlbum => '重命名相册';

  @override
  String get galleryAddToAlbum => '添加到相册';

  @override
  String galleryAddedToAlbum(String name) {
    return '已添加到 $name';
  }

  @override
  String get galleryMoveToAlbum => '移动到相册';

  @override
  String get galleryMove => '移动';

  @override
  String galleryDeleteAlbumTitle(String name) {
    return '删除相册“$name”？';
  }

  @override
  String get galleryDeleteAlbumMessage => '图片会保留在图库中。';

  @override
  String get galleryRemoveFromAlbum => '移出相册';

  @override
  String get galleryRemoveFromAlbumTitle => '移出相册？';

  @override
  String galleryRemoveFromAlbumCount(int count) {
    return '将 $count 张图片移出此相册？';
  }

  @override
  String get galleryRemoveFromAlbumMessage => '图片会保留在图库中。';

  @override
  String get galleryRemove => '移出';

  @override
  String galleryDeleteCount(int count) {
    return '删除 $count 张图片？';
  }

  @override
  String get galleryCannotUndo => '此操作无法撤销。';

  @override
  String get galleryCompare => '对比';

  @override
  String get galleryCopy => '复制';

  @override
  String get galleryShare => '分享';

  @override
  String get galleryPaste => '粘贴';

  @override
  String get galleryAlbum => '相册';

  @override
  String get galleryFavorite => '收藏';

  @override
  String gallerySavedToDeviceCount(int saved, int total) {
    return '已保存 $saved/$total 到设备图库';
  }

  @override
  String galleryExportDialogTitle(int count) {
    return '导出 $count 张图片';
  }

  @override
  String galleryExportedToFolder(int count, String folder) {
    return '已导出 $count 张图片到 $folder';
  }

  @override
  String galleryExportFailed(String error) {
    return '导出失败：$error';
  }

  @override
  String get galleryExportFolderUnavailable => '导出文件夹不可用，请在设置中重新选择。';

  @override
  String galleryImagesCopied(int count) {
    return '$count 张图片已复制';
  }

  @override
  String galleryImagesPasted(int count) {
    return '$count 张图片已粘贴';
  }

  @override
  String get galleryDeleteImage => '删除图片？';

  @override
  String get gallerySavedToDevice => '已保存到设备图库';

  @override
  String get galleryExportImageDialog => '导出图片';

  @override
  String gallerySavedTo(String name) {
    return '已保存到 $name';
  }

  @override
  String galleryResultDownloaded(String name) {
    return '已下载 $name';
  }

  @override
  String galleryResultSaveFailed(String error) {
    return '结果未保存：$error';
  }

  @override
  String get galleryNewImageHidden => '新图已保存，但被当前过滤条件隐藏';

  @override
  String get galleryToggleFavorite => '切换收藏';

  @override
  String get galleryExportImage => '导出图片';

  @override
  String get galleryDeleteImageTooltip => '删除图片';

  @override
  String get galleryNoPrompt => '无提示词';

  @override
  String get galleryNoMetadata => '无元数据';

  @override
  String get galleryCopiedToClipboard => '已复制到剪贴板';

  @override
  String get galleryClipboardUnavailable => '剪贴板不可用';

  @override
  String get galleryPrompt => '提示词';

  @override
  String get galleryImg2img => '图生图';

  @override
  String get galleryCharRef => '角色参考';

  @override
  String get galleryVibe => '氛围';

  @override
  String get gallerySlideshow => '幻灯片';

  @override
  String get galleryAddedAsCharRef => '已添加为角色参考';

  @override
  String get galleryAddedAsVibe => '已添加为氛围迁移';

  @override
  String galleryVibeTransferFailed(String error) {
    return '氛围迁移失败：$error';
  }

  @override
  String get galleryScale => '缩放';

  @override
  String get gallerySteps => '步数';

  @override
  String get gallerySampler => '采样器';

  @override
  String get gallerySeed => '种子';

  @override
  String get galleryResolution => '分辨率';

  @override
  String get galleryEnhance => '增强';

  @override
  String get galleryDirectorTools => '导演工具';

  @override
  String get galleryImport => '导入图片';

  @override
  String get galleryImporting => '正在导入…';

  @override
  String galleryImportProgress(int current, int total) {
    return '正在导入 $current/$total…';
  }

  @override
  String get galleryImportPreparing => '正在准备…';

  @override
  String galleryImportSuccess(int count, int metadata) {
    return '已导入 $count 张图片（$metadata 张含 NovelAI 元数据）';
  }

  @override
  String galleryImportConverted(int count, int converted) {
    return '已导入 $count 张图片（$converted 张已转为 PNG）';
  }

  @override
  String galleryImportFailed(String error) {
    return '导入失败：$error';
  }

  @override
  String get galleryImportToEditor => '导入到编辑器';

  @override
  String get galleryMetadataImported => '元数据已导入编辑器';

  @override
  String get galleryMetadataNotFound => '未找到元数据';

  @override
  String get panelAdvancedSettings => '高级设置';

  @override
  String get panelDimensions => '尺寸';

  @override
  String get panelSeed => '种子';

  @override
  String get panelBatchCount => '批量';

  @override
  String get panelCustom => '自定义';

  @override
  String get panelSteps => '步数';

  @override
  String get panelScale => '缩放';

  @override
  String get panelSampler => '采样器';

  @override
  String get panelStyles => '风格';

  @override
  String get panelManageStyles => '管理风格';

  @override
  String get panelEnabled => '已启用';

  @override
  String get panelNoStylesDefined => '未定义任何风格';

  @override
  String get panelNegativePrompt => '负向提示词';

  @override
  String get panelPresets => '预设';

  @override
  String get panelNoPresetsSaved => '未保存任何预设';

  @override
  String get panelDeletePreset => '删除预设';

  @override
  String panelDeletePresetConfirm(String name) {
    return '删除「$name」？';
  }

  @override
  String get panelDeleteResolution => '删除自定义分辨率';

  @override
  String panelDeleteResolutionConfirm(String name) {
    return '删除自定义分辨率「$name」？';
  }

  @override
  String get panelInputsEmptyTitle => '没有参考输入';

  @override
  String get panelInputsEmptyMessage => '精准参考和氛围迁移是付费工具，当前账号无权使用，列表中也没有已添加的条目。';

  @override
  String get panelInputsHiddenMessage => '精准参考和氛围迁移的栏目已在设置中关闭。';

  @override
  String get panelSaveToAlbum => '保存到相册';

  @override
  String get panelNew => '新建';

  @override
  String get panelNewAlbum => '新建相册';

  @override
  String get panelAlbumName => '相册名称';

  @override
  String get resNormalPortrait => '标准竖屏';

  @override
  String get resNormalLandscape => '标准横屏';

  @override
  String get resNormalSquare => '标准正方形';

  @override
  String get resLargePortrait => '大尺寸竖屏';

  @override
  String get resLargeLandscape => '大尺寸横屏';

  @override
  String get resLargeSquare => '大尺寸正方形';

  @override
  String get resWallpaperPortrait => '壁纸竖屏';

  @override
  String get resWallpaperLandscape => '壁纸横屏';

  @override
  String get toolsHub => '工具中心';

  @override
  String get toolsTitle => '工具';

  @override
  String get toolsWildcards => '随机提示词';

  @override
  String get toolsTagLibrary => '标签库';

  @override
  String get toolsPresets => '预设';

  @override
  String get toolsStyles => '风格';

  @override
  String get toolsReferences => '参考';

  @override
  String get toolsCascadeEditor => '分镜编辑器';

  @override
  String get toolsImg2imgEditor => '图生图编辑器';

  @override
  String get toolsSlideshow => '幻灯片';

  @override
  String get toolsPacks => '资源包';

  @override
  String get toolsTheme => '主题';

  @override
  String get toolsSettings => '设置';

  @override
  String get toolsFeedback => '反馈';

  @override
  String get feedbackTitle => '诊断反馈';

  @override
  String get feedbackIntro =>
      '后台诊断会话会持续保留最近的焦点、输入法、可视区域、交互、性能、网络和面板生命周期事件，并在提交时一次性附在工单中。';

  @override
  String get feedbackPrivacy =>
      '诊断日志不包含正向或负向提示词正文、Seed、图片、认证信息或生成请求正文。日志只保存在当前页面内存中，只有点击提交后才会上传。';

  @override
  String feedbackDebugStatus(int count, int minutes, int dropped) {
    return '后台诊断运行中 · $count 条事件 · 覆盖 $minutes 分钟 · 丢弃 $dropped 条';
  }

  @override
  String get feedbackDescriptionLabel => '发生了什么？（选填）';

  @override
  String get feedbackDescriptionHint => '例如：点击负面提示词后，输入法立刻关闭。';

  @override
  String get feedbackSubmit => '提交诊断反馈';

  @override
  String get feedbackSubmitting => '正在提交…';

  @override
  String get feedbackSubmitted => '反馈已提交';

  @override
  String get feedbackTicketLabel => '工单编号';

  @override
  String get feedbackCopyTicket => '复制工单编号';

  @override
  String get feedbackTicketCopied => '工单编号已复制';

  @override
  String get feedbackSubmitFailed => '提交失败';

  @override
  String get feedbackUnavailable => '诊断反馈仅在经过认证的 Web 应用中可用。';

  @override
  String get feedbackInvalid => '报告被拒绝，请缩短描述后重试。';

  @override
  String get helpTitle => 'NAIWeaver';

  @override
  String get helpShortcuts => '快捷键';

  @override
  String get helpFeatures => '功能';

  @override
  String get helpShortcutWildcard => '从 wildcards/name.txt 随机抽取一行';

  @override
  String get helpShortcutWildcardBrowse => '浏览并插入随机提示词文件';

  @override
  String get helpShortcutHoldDismiss => '关闭标签建议';

  @override
  String get helpShortcutFavorites => '显示所有收藏标签';

  @override
  String get helpShortcutFavCategories => '按分类查看收藏';

  @override
  String get helpShortcutArtistPrefix => '筛选画师标签';

  @override
  String get helpShortcutEnter => '生成（或选择标签建议）';

  @override
  String get helpShortcutDragDrop => '导入生成设置';

  @override
  String get helpFeatureGallery => '图库';

  @override
  String get helpFeatureGalleryDesc => '浏览、收藏、对比、相册分类';

  @override
  String get helpFeatureWildcards => '随机提示词';

  @override
  String get helpFeatureWildcardsDesc => '__pattern__ 从文本文件随机替换';

  @override
  String get helpFeatureStyles => '风格';

  @override
  String get helpFeatureStylesDesc => '自动在提示词中注入前缀/后缀/负向提示';

  @override
  String get helpFeaturePresets => '预设';

  @override
  String get helpFeaturePresetsDesc => '保存与恢复完整生成配置';

  @override
  String get helpFeatureDirectorRef => '导演参考';

  @override
  String get helpFeatureDirectorRefDesc => '用参考图控制角色/风格外观';

  @override
  String get helpFeatureVibeTransfer => '氛围迁移';

  @override
  String get helpFeatureVibeTransferDesc => '用参考图影响构图与氛围';

  @override
  String get helpFeatureCascade => '分镜';

  @override
  String get helpFeatureCascadeDesc => '多镜头连续场景生成';

  @override
  String get helpFeatureImg2img => '图生图';

  @override
  String get helpFeatureImg2imgDesc => '通过重绘与变体编辑/优化图片';

  @override
  String get helpFeatureThemes => '主题';

  @override
  String get helpFeatureThemesDesc => '自定义所有颜色、字体和缩放';

  @override
  String get helpFeaturePacks => '资源包';

  @override
  String get helpFeaturePacksDesc => '将预设、风格、随机提示词导出/导入为 .vpack';

  @override
  String get wildcardManager => '随机提示词管理器';

  @override
  String get wildcardManageDesc => '管理和编辑你的随机提示词文件';

  @override
  String get wildcardFiles => '文件';

  @override
  String get wildcardNew => '新建随机提示词';

  @override
  String get wildcardSelectOrCreate => '选择或创建随机提示词文件';

  @override
  String get wildcardValidateTags => '校验标签';

  @override
  String wildcardRecognized(int valid, int total) {
    return '$valid/$total 已识别';
  }

  @override
  String get wildcardClear => '清空';

  @override
  String get wildcardStartTyping => '开始输入标签…';

  @override
  String wildcardUnrecognized(int count) {
    return '$count 个未识别';
  }

  @override
  String get wildcardCreateTitle => '创建随机提示词';

  @override
  String get wildcardFileName => '文件名';

  @override
  String get wildcardHelp => '随机提示词帮助';

  @override
  String get wildcardHelpTitle => '随机提示词帮助';

  @override
  String get wildcardHelpRandom => '__name__ 从该随机提示词文件随机抽取一行';

  @override
  String get wildcardHelpDotSyntax => '多词名称使用点号';

  @override
  String get wildcardHelpBrowse => '输入 __ 浏览并从自动补全插入随机提示词';

  @override
  String get wildcardHelpNesting => '嵌套';

  @override
  String get wildcardHelpNestingDesc => '随机提示词可引用其他随机提示词（最深 5 层）';

  @override
  String get wildcardHelpTip => '拖动可重新排序文件 — 顺序会用于自动补全';

  @override
  String get wildcardMode => '模式';

  @override
  String get wildcardModeRandom => '随机';

  @override
  String get wildcardModeRandomDesc => '每次使用随机抽取一行';

  @override
  String get wildcardModeSequential => '顺序';

  @override
  String get wildcardModeSequentialDesc => '按顺序循环抽取';

  @override
  String get wildcardModeShuffle => '洗牌';

  @override
  String get wildcardModeShuffleDesc => '先随机打乱所有行，再无重复循环';

  @override
  String get wildcardModeWeighted => '加权';

  @override
  String get wildcardModeWeightedDesc => '使用权重语法（如 10::选项）控制抽取概率';

  @override
  String get wildcardHelpFavorites => '收藏的随机提示词会在标签补全中显示金色边框';

  @override
  String get wildcardDeleteTitle => '删除随机提示词';

  @override
  String wildcardDeleteConfirm(String name) {
    return '确定要删除 \'\'$name\'\' 吗？';
  }

  @override
  String get wildcardRenameTitle => '重命名随机提示词';

  @override
  String get wildcardRenameExists => '已存在同名的随机提示词';

  @override
  String get tagLibTitle => '标签库';

  @override
  String get tagLibPreviewSettings => '预览设置';

  @override
  String get tagLibAddTag => '添加标签';

  @override
  String get tagLibSearchTags => '搜索标签…';

  @override
  String get tagLibAll => '全部';

  @override
  String get tagLibFavorites => '收藏';

  @override
  String get tagLibImages => '图片';

  @override
  String get tagLibSort => '排序：';

  @override
  String get tagLibSortCountDesc => '数量 ↓';

  @override
  String get tagLibSortCountAsc => '数量 ↑';

  @override
  String get tagLibSortAZ => 'A-Z';

  @override
  String get tagLibSortZA => 'Z-A';

  @override
  String get tagLibSortFavsFirst => '收藏优先';

  @override
  String tagLibTagCount(int count) {
    return '$count 个标签';
  }

  @override
  String get tagLibDeleteTag => '删除标签';

  @override
  String tagLibRemoveConfirm(String tag) {
    return '从库中移除「$tag」？';
  }

  @override
  String get tagLibTestTag => '测试标签';

  @override
  String get tagLibAddNewTag => '添加新标签';

  @override
  String get tagLibTagName => '标签名';

  @override
  String get tagLibCount => '数量';

  @override
  String get tagLibAddTagBtn => '添加标签';

  @override
  String get tagLibDeleteExample => '删除示例';

  @override
  String get tagLibDeleteExampleConfirm => '删除此视觉示例？';

  @override
  String tagLibTesting(String tag) {
    return '正在测试：$tag';
  }

  @override
  String get tagLibGeneratingPreview => '正在生成预览…';

  @override
  String get tagLibGenerationFailed => '生成失败';

  @override
  String get tagLibExampleSaved => '示例已保存';

  @override
  String get tagLibSaveAsExample => '保存为示例';

  @override
  String get tagLibPreviewSettingsTitle => '预览设置';

  @override
  String get tagLibPositivePromptBase => '正向提示词（基础）';

  @override
  String get tagLibNegativePrompt => '负向提示词';

  @override
  String get tagLibSampler => '采样器';

  @override
  String get tagLibSteps => '步数';

  @override
  String get tagLibWidth => '宽度';

  @override
  String get tagLibHeight => '高度';

  @override
  String get tagLibScale => '缩放';

  @override
  String get tagLibSeed => '种子';

  @override
  String get tagLibRandom => '随机';

  @override
  String get tagDetailViewOnDanbooru => '在 Danbooru 查看';

  @override
  String get tagDetailNoWiki => '该标签暂无 Wiki 说明。';

  @override
  String get tagDetailCheckDanbooru => '前往 Danbooru 查看';

  @override
  String get tagDetailLicense => '标签说明 © Danbooru 贡献者，CC-BY-SA-4.0';

  @override
  String get presetManager => '预设管理器';

  @override
  String get presetManageDesc => '管理和编辑生成预设';

  @override
  String get presetList => '预设';

  @override
  String get presetNew => '新建预设';

  @override
  String presetCharsInfo(int chars, int ints) {
    return '$chars 角色，$ints 互动';
  }

  @override
  String presetCharsRefsInfo(int chars, int ints, int refs) {
    return '$chars 角色，$ints 互动，$refs 参考';
  }

  @override
  String get presetSelectToEdit => '选择要编辑的预设';

  @override
  String get presetIdentity => '标识';

  @override
  String get presetName => '名称';

  @override
  String get presetPrompts => '提示词';

  @override
  String get presetPrompt => '提示词';

  @override
  String get presetNegativePrompt => '负向提示词';

  @override
  String get presetGenSettings => '生成设置';

  @override
  String get presetWidth => '宽度';

  @override
  String get presetHeight => '高度';

  @override
  String get presetScale => '缩放';

  @override
  String get presetSteps => '步数';

  @override
  String get presetSampler => '采样器';

  @override
  String get presetCharsAndInteractions => '角色与互动';

  @override
  String get presetNoChars => '此预设未保存角色';

  @override
  String presetCharacterN(int n) {
    return '角色 $n';
  }

  @override
  String get presetInteractions => '互动';

  @override
  String get presetReferences => '参考';

  @override
  String get presetNoRefs => '此预设未保存参考';

  @override
  String get presetProcessing => '处理中…';

  @override
  String get presetAddReference => '添加参考';

  @override
  String get presetDeleteTitle => '删除预设';

  @override
  String presetDeleteConfirm(String name) {
    return '确定要删除「$name」吗？';
  }

  @override
  String get presetOverwriteTitle => '覆盖预设';

  @override
  String presetOverwriteConfirm(String name) {
    return '名为「$name」的预设已存在。是否覆盖？';
  }

  @override
  String get styleEditor => '风格编辑器';

  @override
  String get styleManageDesc => '管理提示词片段和风格标签';

  @override
  String get styleList => '风格';

  @override
  String get styleNew => '新建风格';

  @override
  String get styleResetDefaults => '重置风格为默认值';

  @override
  String get styleSelectToEdit => '选择要编辑的风格';

  @override
  String get styleIdentity => '标识';

  @override
  String get styleName => '名称';

  @override
  String get styleDefaultOnLaunch => '启动时默认启用';

  @override
  String get styleTargetPrompt => '目标提示词';

  @override
  String get stylePositive => '正向';

  @override
  String get styleNegative => '负向';

  @override
  String get styleNegativeContent => '负向内容';

  @override
  String get stylePositiveContent => '正向内容';

  @override
  String get styleContent => '内容';

  @override
  String get stylePlacement => '位置';

  @override
  String get styleBeginningPrefix => '开头（前缀）';

  @override
  String get styleEndSuffix => '结尾（后缀）';

  @override
  String get styleDeleteTitle => '删除风格';

  @override
  String styleDeleteConfirm(String name) {
    return '确定要删除「$name」吗？';
  }

  @override
  String get styleOverwriteTitle => '覆盖风格';

  @override
  String styleOverwriteConfirm(String name) {
    return '名为「$name」的风格已存在。是否覆盖？';
  }

  @override
  String get refPreciseReferences => '精准参考';

  @override
  String get refShortLabel => '参考';

  @override
  String get refVibeTransfer => '氛围迁移';

  @override
  String get refNameHint => '名称';

  @override
  String get refClearAll => '清空全部';

  @override
  String get refSavedSection => '已保存';

  @override
  String get refSaveReference => '保存参考';

  @override
  String refReferenceCount(int count) {
    return '$count 个参考';
  }

  @override
  String get refNoReferencesAdded => '未添加任何参考';

  @override
  String get refEmptyDescription => '上传参考图以在生成中保持角色外观或艺术风格。';

  @override
  String get refAddReference => '添加参考';

  @override
  String get refEditorTitle => '参考编辑器';

  @override
  String get refTypeLabel => '参考类型';

  @override
  String get refStrength => '强度';

  @override
  String get refFidelity => '保真度';

  @override
  String get refStrengthShort => '强';

  @override
  String get refFidelityShort => '保';

  @override
  String get refTypeCharacter => '角色';

  @override
  String get refTypeStyle => '风格';

  @override
  String get refTypeCharAndStyle => '角色+风格';

  @override
  String get refSaveVibe => '保存氛围';

  @override
  String refVibeCount(int count) {
    return '$count 个氛围';
  }

  @override
  String get refNoVibesAdded => '未添加任何氛围';

  @override
  String get refVibeEmptyDescription => '上传参考图以将艺术风格和氛围迁移到生成内容。';

  @override
  String get refAddVibe => '添加氛围';

  @override
  String get refVibeLabel => '氛围';

  @override
  String get refVibeRemoveConfirm => '从列表中移除这个氛围？';

  @override
  String get refVibeEditorTitle => '氛围编辑器';

  @override
  String get refInfoExtracted => '信息已提取';

  @override
  String get refInfoExtractedShort => '信';

  @override
  String get refApiKeyMissing => '缺少或无效的 API Key';

  @override
  String get refImageProcessFailed => '无法读取该图片，请换一张试试。';

  @override
  String get refVibeNoPermission => '当前账号没有编码氛围的权限。';

  @override
  String get refErrorPointsInsufficient => '点数不足，无法编码该氛围。';

  @override
  String get refErrorSessionExpired => '登录已失效，请重新登录。';

  @override
  String get refErrorNetwork => '网络连接失败，请检查网络后重试。';

  @override
  String get refErrorServiceUnavailable => '服务繁忙或暂时不可用，请稍后重试。';

  @override
  String get refVibeEncodeFailed => '氛围编码失败，请稍后重试。';

  @override
  String get refLoadSaved => '加载已保存';

  @override
  String get refPickImage => '选择图片';

  @override
  String get refBrowseFiles => '浏览文件';

  @override
  String get refNoSavedRefs => '暂无已保存的参考';

  @override
  String get refRemove => '移除';

  @override
  String get refLibrarySaved => '已保存到素材库';

  @override
  String get refLibrarySaveFailed => '无法写入素材库，存储空间可能已满。';

  @override
  String get packTitle => 'NAIWeaver 资源包';

  @override
  String get packDesc => '将预设、风格、随机提示词导出/导入为 .vpack 文件。';

  @override
  String get packExportLabel => '导出包';

  @override
  String get packExportDesc => '打包预设、风格和随机提示词';

  @override
  String get packImportLabel => '导入包';

  @override
  String get packImportDesc => '加载 .vpack 文件';

  @override
  String get packGalleryExport => '图库导出';

  @override
  String get packGalleryExportDesc => '将图库图片按相册文件夹导出为 ZIP。';

  @override
  String get packExportGalleryZip => '导出图库为 ZIP';

  @override
  String get packExportGalleryZipDesc => '保留相册文件夹结构';

  @override
  String packFailedRead(String error) {
    return '读取包失败：$error';
  }

  @override
  String get packExportDialogTitle => '导出包';

  @override
  String get packName => '包名称';

  @override
  String get packDescriptionOptional => '描述（可选）';

  @override
  String packPresetsSection(int selected, int total) {
    return '预设（$selected/$total）';
  }

  @override
  String packStylesSection(int selected, int total) {
    return '风格（$selected/$total）';
  }

  @override
  String packWildcardsSection(int selected, int total) {
    return '随机提示词（$selected/$total）';
  }

  @override
  String packSavedRefsSection(int selected, int total) {
    return '已保存的参考 ($selected/$total)';
  }

  @override
  String packSavedVibesSection(int selected, int total) {
    return '已保存的氛围 ($selected/$total)';
  }

  @override
  String packCharacterPresetsSection(int selected, int total) {
    return '角色预设 ($selected/$total)';
  }

  @override
  String packThemesSection(int selected, int total) {
    return '主题 ($selected/$total)';
  }

  @override
  String packAlbumsSection(int selected, int total) {
    return '相册 ($selected/$total)';
  }

  @override
  String get packSettingsSection => '应用与点唱机设置';

  @override
  String get packSettingsItem => '应用与点唱机设置';

  @override
  String get packImportRestartHint => '已导入。请重启应用以完全应用设置和主题。';

  @override
  String get packExportSuccess => '包导出成功';

  @override
  String packExportFailed(String error) {
    return '导出失败：$error';
  }

  @override
  String get packImportDialogTitle2 => '导入包';

  @override
  String packImportCount(int count) {
    return '导入（$count）';
  }

  @override
  String get packImportSuccess => '包导入成功';

  @override
  String packImportFailed(String error) {
    return '导入失败：$error';
  }

  @override
  String get packRefLibrarySaveFailed => '无法保存已存参考图，请释放存储空间后重新导入。';

  @override
  String get packSelectAll => '全选';

  @override
  String get packSelectNone => '全不选';

  @override
  String get packExportGalleryTitle => '导出图库';

  @override
  String get packAlbums => '相册';

  @override
  String packUnsortedCount(int count) {
    return '未分类（$count）';
  }

  @override
  String get packOptions => '选项';

  @override
  String get packStripMetadata => '移除元数据';

  @override
  String get packFavoritesOnly => '仅收藏';

  @override
  String packExportCount(int count) {
    return '导出（$count）';
  }

  @override
  String get packSaveDialogTitle => '保存 NAIWeaver 包';

  @override
  String get packExportGalleryZipDialog => '导出图库 ZIP';

  @override
  String packExportedToZip(int count) {
    return '已导出 $count 张图片到 ZIP';
  }

  @override
  String get themeSelectToEdit => '选择要编辑的主题';

  @override
  String get themeList => '主题';

  @override
  String get themeNew => '新建主题';

  @override
  String get themeSave => '保存';

  @override
  String get themeReset => '重置';

  @override
  String get themePreview => '预览';

  @override
  String get themeColors => '颜色';

  @override
  String get themeColorBackground => '背景';

  @override
  String get themeColorSurfaceHigh => '上层界面';

  @override
  String get themeColorSurfaceMid => '中层界面';

  @override
  String get themeColorTextPrimary => '主要文字';

  @override
  String get themeColorTextSecondary => '次要文字';

  @override
  String get themeColorTextTertiary => '三级文字';

  @override
  String get themeColorTextDisabled => '禁用文字';

  @override
  String get themeColorTextMinimal => '极简文字';

  @override
  String get themeColorBorderStrong => '强边框';

  @override
  String get themeColorBorderMedium => '中等边框';

  @override
  String get themeColorBorderSubtle => '弱边框';

  @override
  String get themeColorAccent => '强调色';

  @override
  String get themeColorAccentEdit => '编辑强调色';

  @override
  String get themeColorAccentSuccess => '成功强调色';

  @override
  String get themeColorAccentDanger => '危险强调色';

  @override
  String get themeColorLogo => 'Logo';

  @override
  String get themeColorCascade => '分镜';

  @override
  String get themeReferences => '参考';

  @override
  String get themeColorVibeTransfer => '氛围迁移';

  @override
  String get themeColorRefCharacter => '角色参考';

  @override
  String get themeColorRefStyle => '风格参考';

  @override
  String get themeColorRefCharStyle => '角色+风格参考';

  @override
  String get themeColorFavorite => '收藏';

  @override
  String get themeColorCharacter => '角色';

  @override
  String get themeColorPositive => '正向';

  @override
  String get themeColorNegative => '负向';

  @override
  String get themeFont => '字体';

  @override
  String get themeTextScale => '文字大小';

  @override
  String get themeHeaderScale => '标题大小';

  @override
  String get themeTitleScale => '面板标题大小';

  @override
  String get themeButtonScale => '按钮大小';

  @override
  String get themeSmall => '小';

  @override
  String get themeLarge => '大';

  @override
  String get themePromptInput => '提示词输入框';

  @override
  String get themeFontSize => '字号';

  @override
  String get themeHeightLabel => '高度';

  @override
  String themeLines(int count) {
    return '$count 行';
  }

  @override
  String get themeBrightMode => '明亮模式';

  @override
  String get themeBrightText => '明亮文字';

  @override
  String get themeBrightDesc => '使用更亮的文字颜色以提升可读性';

  @override
  String get themePanelLayout => '面板布局';

  @override
  String get themePanelLayoutDesc => '拖动可重新排序高级设置区域';

  @override
  String get themeDeleteTitle => '删除主题';

  @override
  String themeDeleteConfirm(String name) {
    return '确定要删除「$name」吗？';
  }

  @override
  String get themeNewTitle => '新建主题';

  @override
  String get themeCustomTheme => '自定义主题';

  @override
  String get themeThemeName => '主题名称';

  @override
  String themeCreateFailed(String error) {
    return '创建主题失败：$error';
  }

  @override
  String get themeSectionDimSeed => '尺寸 + 种子';

  @override
  String get themeSectionStepsScale => '步数 + 缩放';

  @override
  String get themeSectionSamplerPost => '采样器 + 后期';

  @override
  String get themeSectionStyles => '风格';

  @override
  String get themeSectionNegPrompt => '负向提示词';

  @override
  String get themeSectionPresets => '预设';

  @override
  String get themeSectionSaveAlbum => '保存到相册';

  @override
  String get themePreviewHeader => '标题文字';

  @override
  String get themePreviewSecondary => '次要文字内容';

  @override
  String get themePreviewHint => '提示 / 三级文字';

  @override
  String get themePreviewGenerate => '生成';

  @override
  String get themePreviewEdit => '编辑';

  @override
  String get cascadeEditorLabel => '分镜编辑器';

  @override
  String get cascadeSavedToLibrary => '分镜已保存到库';

  @override
  String get cascadeNoBeatSelected => '未选择镜头';

  @override
  String get cascadeScenePrompt => '场景 / 动作';

  @override
  String get cascadeSceneSubLabel => '发生什么 + 取景';

  @override
  String get cascadeSceneHint =>
      '正在发生什么：如 2girls, hugging, wide shot, from above';

  @override
  String get cascadeEnvironmentPrompt => '环境提示词';

  @override
  String get cascadeEnvSubLabel => '发生的地点';

  @override
  String get cascadeEnvHint => '地点：如 森林、夜晚、室内、电影光';

  @override
  String get cascadeApplyToAll => '应用到全部';

  @override
  String get cascadeSceneApplied => '场景已应用到所有节拍';

  @override
  String get cascadeCharacterSlots => '角色槽位';

  @override
  String cascadeCharacterSlotN(int n) {
    return '角色槽位 $n';
  }

  @override
  String get cascadePosition => '位置';

  @override
  String get cascadeAiPosition => 'AI 位置';

  @override
  String get cascadePositivePrompt => '正向提示词';

  @override
  String get cascadeCharHint => '角色标签、外观、状态…';

  @override
  String get cascadeNegativePrompt => '负向提示词';

  @override
  String get cascadeAvoidHint => '不想要的内容…';

  @override
  String get cascadeLinkAction => '关联动作';

  @override
  String get cascadeBeatSettings => '镜头设置';

  @override
  String get cascadeResolution => '分辨率';

  @override
  String get cascadeSampler => '采样器';

  @override
  String get cascadeSteps => '步数';

  @override
  String get cascadeScale => '缩放';

  @override
  String get cascadeStyles => '风格';

  @override
  String get cascadeNoStyles => '无可用风格';

  @override
  String get cascadeLibrary => '分镜库';

  @override
  String cascadeSequencesSaved(int count) {
    return '已保存 $count 个序列';
  }

  @override
  String get cascadeNew => '新建分镜';

  @override
  String get cascadeNoCascades => '未找到分镜';

  @override
  String cascadeBeatsAndSlots(int beats, int slots) {
    return '$beats 镜头 • $slots 角色槽';
  }

  @override
  String get cascadeCreateNew => '创建分镜';

  @override
  String get cascadeName => '分镜名称';

  @override
  String get cascadeCharSlotsLabel => '角色槽位';

  @override
  String get cascadeAutoPosition => '自动位置（由 AI 决定）';

  @override
  String get cascadeDeleteTitle => '删除分镜？';

  @override
  String cascadeDeleteConfirm(String name) {
    return '确定要删除「$name」吗？';
  }

  @override
  String get cascadeSelect => '选择分镜';

  @override
  String get cascadeNoSaved => '未找到保存的分镜';

  @override
  String cascadeCharactersAndBeats(int chars, int beats) {
    return '$chars 角色 • $beats 镜头';
  }

  @override
  String cascadeCharTags(int n) {
    return '角色 $n 标签';
  }

  @override
  String get cascadeGlobalScene => '全局场景（应用于每个镜头的标签）';

  @override
  String get cascadeGlobalStyle => '全局风格 / 注入';

  @override
  String get cascadeCaptionHint => '为该镜头添加旁白...（显示在预览上）';

  @override
  String get cascadeCaptionToggle => '显示 / 隐藏字幕';

  @override
  String get cascadeExportTooltip => '导出（带字幕）';

  @override
  String get cascadeExportBeat => '导出该镜头（字幕已烧录）';

  @override
  String get cascadeExportStripVertical => '故事板 — 纵向';

  @override
  String get cascadeExportStripHorizontal => '故事板 — 横向';

  @override
  String get cascadeExportSaved => '已导出';

  @override
  String get cascadeExportFailed => '导出失败';

  @override
  String get cascadeStripDownscaled => '故事板已缩小以适应内存限制';

  @override
  String cascadeRegenerateBeat(int n) {
    return '重新生成镜头 $n';
  }

  @override
  String cascadeGenerateBeat(int n) {
    return '生成镜头 $n';
  }

  @override
  String get cascadeSkipToNext => '跳到下一个';

  @override
  String get cascadeBeatRenderError => '无法构建此镜头。请检查是否已设置角色外观。';

  @override
  String get cascadeStartCasting => '分配角色';

  @override
  String get cascadeBackToLibrary => '库';

  @override
  String get cascadeUnsavedTitle => '有未保存更改';

  @override
  String get cascadeUnsavedMessage => '此分镜有未保存更改，是否放弃？';

  @override
  String get cascadeDiscard => '放弃';

  @override
  String get cascadeExitCascade => '退出分镜';

  @override
  String get img2imgResult => '结果';

  @override
  String get img2imgSource => '原图';

  @override
  String get img2imgCanvas => '画布';

  @override
  String get img2imgUseAsSource => '设为原图';

  @override
  String get img2imgBackToPicker => '返回选择器';

  @override
  String get img2imgGenerating => '生成中…';

  @override
  String get img2imgGenerate => '生成';

  @override
  String img2imgGenerationFailed(String error) {
    return '生成失败：$error';
  }

  @override
  String get img2imgSettings => '图生图设置';

  @override
  String get img2imgPrompt => '提示词';

  @override
  String get img2imgPromptHint => '描述要生成的内容…';

  @override
  String get img2imgNegative => '负向';

  @override
  String get img2imgNegativeHint => '不想要的内容…';

  @override
  String get img2imgStrength => '强度';

  @override
  String get img2imgNoise => '噪声';

  @override
  String get img2imgMaskBlur => '蒙版模糊';

  @override
  String get img2imgColorCorrect => '色彩校正';

  @override
  String get img2imgSourceInfo => '原图信息';

  @override
  String img2imgMaskStrokes(int count) {
    return '蒙版：$count 笔';
  }

  @override
  String get img2imgClearMaskTitle => '清除蒙版？';

  @override
  String get img2imgClearMaskMessage => '将移除全部蒙版笔画，此操作无法撤销。';

  @override
  String get img2imgClearMaskConfirm => '清除';

  @override
  String get img2imgMaskUndoStroke => '撤销笔画';

  @override
  String get img2imgMaskClearTooltip => '清除遮罩';

  @override
  String get img2imgBrushRound => '圆形笔刷';

  @override
  String get img2imgBrushSquare => '方形笔刷';

  @override
  String get img2imgBrushSize => '大小';

  @override
  String get img2imgMaskDisplay => '遮罩显示设置';

  @override
  String get img2imgMaskSave => '保存遮罩';

  @override
  String get img2imgMaskLoad => '加载遮罩';

  @override
  String get img2imgMaskSaved => '遮罩已保存';

  @override
  String get img2imgMaskColor => '颜色';

  @override
  String get img2imgMaskOpacity => '不透明度';

  @override
  String get img2imgMaskPatternSolid => '实心';

  @override
  String get img2imgMaskPatternStripe => '条纹';

  @override
  String get img2imgMaskPatternCross => '网格';

  @override
  String get img2imgMaskBorder => '边框';

  @override
  String get img2imgMaskBorderTooltip => '显示遮罩边框';

  @override
  String get img2imgNoMask => '无蒙版（全图生图）';

  @override
  String get img2imgImportPrompt => '导入提示词';

  @override
  String get img2imgImportPromptDesc => '从原图元数据自动填充提示词';

  @override
  String get img2imgUploadFromDevice => '从设备上传';

  @override
  String get img2imgUploadFromDeviceDesc => '从相册或文件选择图片';

  @override
  String get img2imgBlankCanvas => '空白画布';

  @override
  String get img2imgBlankCanvasDesc => '创建空白画布进行绘制';

  @override
  String get img2imgBlankCanvasSize => '画布尺寸';

  @override
  String get img2imgPickerTitle => '选择源图像';

  @override
  String get img2imgPickerDesc => '选择一张图像作为图生图或局部重绘的基础';

  @override
  String get img2imgUseCurrent => '使用当前生成图';

  @override
  String get img2imgUseCurrentDesc => '将最近生成的图像作为源图像';

  @override
  String get slideshowTitle => '幻灯片';

  @override
  String get slideshowPlayAll => '播放全部';

  @override
  String get slideshowPrevious => '上一张';

  @override
  String get slideshowNext => '下一张';

  @override
  String get slideshowPause => '暂停';

  @override
  String get slideshowResume => '继续播放';

  @override
  String get slideshowMusic => '音乐';

  @override
  String get slideshowEnableMusic => '启用音乐';

  @override
  String get slideshowMusicVolume => '音乐音量';

  @override
  String get slideshowKaraoke => '卡拉 OK 歌词';

  @override
  String get slideshowSongsHint => '歌曲（点击选择，留空 = 全部）';

  @override
  String get slideshowSoundFont => '音色库';

  @override
  String get slideshowSoundFontDefault => '默认';

  @override
  String get slideshowCategoryAll => '全部';

  @override
  String get slideshowConfigs => '配置';

  @override
  String get slideshowNewConfig => '新建配置';

  @override
  String get slideshowNoConfigs => '暂无幻灯片配置。\n点击 + 创建。';

  @override
  String get slideshowSelectOrCreate => '选择或创建幻灯片配置';

  @override
  String get slideshowNameLabel => '名称';

  @override
  String get slideshowSourceLabel => '来源';

  @override
  String get slideshowTransition => '转场';

  @override
  String get slideshowTransitionDuration => '转场时长';

  @override
  String get slideshowTiming => '时序';

  @override
  String get slideshowSlideDuration => '单张时长';

  @override
  String get slideshowKenBurns => '动态缩放效果';

  @override
  String get slideshowEnabled => '已启用';

  @override
  String get slideshowIntensity => '强度';

  @override
  String get slideshowManualZoom => '手动缩放';

  @override
  String get slideshowPlayback => '播放';

  @override
  String get slideshowShuffle => '随机';

  @override
  String get slideshowLoop => '循环';

  @override
  String get slideshowDefault => '默认';

  @override
  String get slideshowUseAsDefault => '设为默认幻灯片';

  @override
  String get slideshowPlay => '播放幻灯片';

  @override
  String get slideshowTransFade => '淡入淡出';

  @override
  String get slideshowTransSlideL => '左滑';

  @override
  String get slideshowTransSlideR => '右滑';

  @override
  String get slideshowTransSlideUp => '上滑';

  @override
  String get slideshowTransZoom => '缩放';

  @override
  String get slideshowTransXZoom => '横向缩放';

  @override
  String get slideshowSourceAllImages => '所有图片';

  @override
  String get slideshowSourceAlbum => '相册';

  @override
  String get slideshowSourceFavorites => '收藏';

  @override
  String slideshowSourceCustom(int count) {
    return '$count 自定义';
  }

  @override
  String get slideshowDeleteConfig => '删除配置';

  @override
  String slideshowDeleteConfirm(String name) {
    return '删除「$name」？';
  }

  @override
  String get slideshowImageSource => '图片来源';

  @override
  String get slideshowAllImages => '所有图片';

  @override
  String slideshowImageCount(int count) {
    return '$count 张图片';
  }

  @override
  String get slideshowFavoritesLabel => '收藏';

  @override
  String get slideshowAlbumLabel => '相册';

  @override
  String get slideshowCustomSelection => '自定义选择';

  @override
  String slideshowSelectedCount(int count) {
    return '已选择 $count 项';
  }

  @override
  String get slideshowNoAlbums => '未创建相册';

  @override
  String get slideshowSelectAlbum => '选择相册';

  @override
  String slideshowCustomCount(int selected, int total) {
    return '$selected/$total 已选择';
  }

  @override
  String get slideshowDeselectAll => '取消全选';

  @override
  String get slideshowSelectAll => '全选';

  @override
  String get slideshowNoImages => '无图片可显示';

  @override
  String get slideshowGoBack => '返回';

  @override
  String demoImagesSelected(int count) {
    return '已选择 $count 张图片';
  }

  @override
  String get demoAll => '全部';

  @override
  String get demoClear => '清空';

  @override
  String get demoNoImages => '图库无图片';

  @override
  String get demoGridSize => '切换网格大小';

  @override
  String get cascadeBeatTimeline => '镜头时间线';

  @override
  String cascadeBeatsCount(int count) {
    return '$count 个镜头';
  }

  @override
  String cascadeBeatN(int n) {
    return '镜头 $n';
  }

  @override
  String get cascadeCloneBeat => '复制镜头';

  @override
  String get cascadeRemoveBeat => '移除镜头';

  @override
  String get cascadeRemoveBeatMessage => '此节拍及其提示词将从序列中移除。';

  @override
  String get cascadeRemoveActionTag => '移除动作标签';

  @override
  String get settingsCheckForUpdates => '检查更新';

  @override
  String get settingsUpdateAvailable => '有更新可用';

  @override
  String settingsUpdateAvailableDesc(String version) {
    return '新版本 $version 已可用。';
  }

  @override
  String get settingsUpdateDownload => '下载';

  @override
  String get settingsUpToDate => '已是最新版本！';

  @override
  String get settingsUpdateCheckFailed => '检查更新失败';

  @override
  String get settingsUpdateDownloading => '正在下载更新…';

  @override
  String settingsUpdateProgress(String received, String total) {
    return '$received / $total';
  }

  @override
  String get settingsUpdateInstalling => '正在启动安装程序…';

  @override
  String get settingsUpdateRestartPrompt => 'NAIWeaver 将关闭以应用更新，然后自动重新打开。';

  @override
  String get settingsUpdateDownloadFailed => '下载失败';

  @override
  String get settingsUpdateInstallFailed => '无法启动安装程序';

  @override
  String get settingsUpdateOpenInBrowser => '在浏览器中打开';

  @override
  String get settingsUpdateApply => '更新并重启';

  @override
  String get mainAnlas => '点';

  @override
  String get mainEstimatedCostLabel => '预计';

  @override
  String get mainEstimatedCostTooltip => '生成前预估；完成后按 NovelAI 实际扣点校准';

  @override
  String get mainEstimatedCostBase => '基础';

  @override
  String get mainEstimatedCostReference => '参考图';

  @override
  String get mainEstimatedCostVibe => '氛围迁移';

  @override
  String get mainEstimatedCostSerialImages => '串行张数';

  @override
  String get settingsAnlasTracker => 'Anlas 追踪';

  @override
  String get settingsAnlasTrackerDesc => '在顶部栏显示 Anlas 余额';

  @override
  String get settingsCopyButton => '复制到剪贴板';

  @override
  String get settingsCopyButtonDesc => '在生成的图片上显示复制按钮';

  @override
  String get settingsHideTagValues => '隐藏标签数值';

  @override
  String get settingsHideTagValuesDesc => '在自动补全建议中隐藏标签数量';

  @override
  String get settingsFontSize => '字体大小';

  @override
  String get settingsFontSizeDesc => '缩放所有界面文字，默认 100%。';

  @override
  String get settingsOpenLinkTitle => '打开外部链接';

  @override
  String get settingsOpenLinkBody => '即将离开 NAIWeaver 并打开新窗口：';

  @override
  String get settingsOpenLinkConfirm => '打开链接';

  @override
  String get canvasEditorTitle => '画布编辑器';

  @override
  String get canvasEditInCanvas => '画布';

  @override
  String get canvasPaint => '画笔';

  @override
  String get canvasErase => '擦除';

  @override
  String get canvasSize => '大小';

  @override
  String get canvasOpacity => '不透明度';

  @override
  String get canvasUndo => '撤销';

  @override
  String get canvasRedo => '重做';

  @override
  String get canvasFlatten => '合并图层';

  @override
  String get canvasFlattenSend => '合并并发送';

  @override
  String get canvasBack => '返回图生图';

  @override
  String get canvasDiscardTitle => '放弃更改？';

  @override
  String get canvasDiscardMessage => '你有未保存的画笔笔触，是否放弃？';

  @override
  String get canvasDiscard => '放弃';

  @override
  String canvasFlattenFailed(String error) {
    return '合并失败：$error';
  }

  @override
  String get canvasColor => '颜色';

  @override
  String get canvasLayers => '图层';

  @override
  String get canvasLayerAdd => '添加图层';

  @override
  String get canvasLayerDelete => '删除图层';

  @override
  String get canvasLayerDuplicate => '复制图层';

  @override
  String get canvasLayerOpacity => '不透明度';

  @override
  String get canvasLayerBlendMode => '混合模式';

  @override
  String get canvasLayerDeleteConfirm => '删除此图层？笔触将会丢失。';

  @override
  String get canvasLayerClear => '清空图层';

  @override
  String get canvasLayerClearConfirm => '清空此图层所有笔触？';

  @override
  String get canvasLine => '直线';

  @override
  String get canvasRectangle => '矩形';

  @override
  String get canvasCircle => '圆形';

  @override
  String get canvasEyedropper => '取色';

  @override
  String get canvasTransform => '移动';

  @override
  String get canvasImportImage => '导入图片';

  @override
  String get canvasHelp => '画布帮助';

  @override
  String get canvasSmooth => '平滑';

  @override
  String get canvasFill => '填充';

  @override
  String get canvasText => '文字';

  @override
  String get canvasTextHint => '输入文字…';

  @override
  String get canvasTextSize => '大小';

  @override
  String get canvasTextFont => '字体';

  @override
  String get canvasTextSpacing => '间距';

  @override
  String get canvasTextDefault => '默认';

  @override
  String get canvasSelectTool => '选区';

  @override
  String get canvasLassoTool => '套索';

  @override
  String get canvasBlurTool => '模糊';

  @override
  String get canvasCloneTool => '仿制';

  @override
  String get canvasResize => '调整画布大小';

  @override
  String get canvasApply => '应用';

  @override
  String get canvasDeleteSelection => '删除选区内容';

  @override
  String get canvasPaletteTapHint => '点按：选择  •  长按：替换为当前颜色';

  @override
  String get canvasPaletteHoldHint => '长按替换';

  @override
  String get settingsOutputFolder => '输出文件夹';

  @override
  String get settingsOutputFolderDesc => '选择生成图片的保存位置';

  @override
  String get settingsFilenamePattern => '文件名模式';

  @override
  String get settingsFilenamePatternDesc =>
      '保存图像的自定义名称。可用标记: <prompt>, <seed>, <album:fallback>, <year>, <month>, <day>, <hours>, <minutes>, <seconds>, <date>, <time>, <digits:0000>。留空使用 NAI 风格默认值。';

  @override
  String get settingsSavePathPattern => '保存子文件夹模式';

  @override
  String get settingsSavePathPatternDesc =>
      '在输出文件夹下自动创建子文件夹，例如 <year>/<month>/<day>。使用相同标记。留空则不创建。';

  @override
  String get settingsPatternPreview => '预览';

  @override
  String get settingsOutputFolderDefault => '默认（应用存储）';

  @override
  String get settingsOutputFolderBrowse => '浏览';

  @override
  String get settingsFolderUseDefault => '使用默认文件夹';

  @override
  String get settingsUseSdCard => '使用SD卡';

  @override
  String get settingsSdDialogTitle => '将输出移至SD卡';

  @override
  String get settingsSdUninstallWarning =>
      'SD卡上的图片保存在应用专属文件夹 (Android/data) 中。卸载应用时,Android会同时删除本机和SD卡上的该文件夹。请先将重要图片导出到其他位置。';

  @override
  String settingsSdExistingInfo(int count, String size) {
    return '可将$count个现有文件($size)移动到SD卡。';
  }

  @override
  String get settingsSdMoveButton => '移动现有文件';

  @override
  String get settingsSdFreshButton => '直接使用(不移动)';

  @override
  String get settingsSdAlready => '输出文件夹已在SD卡上';

  @override
  String settingsSdNotEnoughSpace(String needed, String available) {
    return 'SD卡空间不足:需要 $needed,可用 $available';
  }

  @override
  String get settingsSdMoving => '正在移动到SD卡… 请保持应用打开。';

  @override
  String settingsSdMoveDone(int count) {
    return '已将$count个文件移动到SD卡';
  }

  @override
  String settingsSdMoveFailed(int count) {
    return '$count个文件无法移动 — 点按\"使用SD卡\"重试';
  }

  @override
  String settingsSdMovePaused(int count) {
    return '移动已暂停 — 剩余$count个文件。点按\"使用SD卡\"继续。';
  }

  @override
  String get settingsSdResumeTitle => '继续移动到SD卡';

  @override
  String settingsSdResumeBody(int count) {
    return '上次移动还剩$count个文件。现在继续吗?';
  }

  @override
  String get settingsSdResume => '继续';

  @override
  String get resCustomEntry => '自定义…';

  @override
  String get resCustomDialogTitle => '自定义分辨率';

  @override
  String get resCustomWidth => '宽度';

  @override
  String get resCustomHeight => '高度';

  @override
  String get resCustomName => '名称（可选）';

  @override
  String get resCustomUseOnce => '仅使用一次';

  @override
  String get resCustomSaveAndUse => '保存并使用';

  @override
  String get resCustomMustBeMultiple => '必须是 64 的倍数';

  @override
  String get resCustomOutOfRange => '必须在 64–2048 之间';

  @override
  String get themeSectionCharacters => '角色';

  @override
  String get charEditorTitle => '角色';

  @override
  String get charEditorExpanded => '展开';

  @override
  String get charEditorCompact => '紧凑';

  @override
  String get charEditorAutoPosition => '自动';

  @override
  String get charEditorUsingCompactShelf => '在提示词下方使用紧凑栏';

  @override
  String get charEditorCharacterName => '角色名称';

  @override
  String get charEditorPromptHint => '角色标签、外观…';

  @override
  String get charEditorUcHint => '不想要的标签…';

  @override
  String get charEditorShowUc => '负向';

  @override
  String get charEditorShowPosition => '位置';

  @override
  String get charEditorShowPresets => '预设';

  @override
  String get charEditorShowTitle => '标题';

  @override
  String get charEditorAiDecidesPosition => 'AI 决定位置';

  @override
  String get charEditorAddCharacter => '添加角色';

  @override
  String get charEditorCharacterLimitReached => '已达角色上限（6）';

  @override
  String charEditorDeleteConfirm(String name) {
    return '删除「$name」？';
  }

  @override
  String get charEditorDeleteCharacter => '删除角色';

  @override
  String get charEditorInteractions => '互动';

  @override
  String get charEditorAddInteraction => '添加互动';

  @override
  String charEditorInteractionDisplay(
    String source,
    String target,
    String action,
  ) {
    return '$source → $target：$action';
  }

  @override
  String get charEditorSavePreset => '保存预设';

  @override
  String get charEditorPresetName => '预设名称';

  @override
  String get charEditorNoPresets => '未保存角色预设';

  @override
  String get charEditorSelectSource => '来源角色';

  @override
  String get charEditorSelectTarget => '目标角色';

  @override
  String charEditorCharacterN(int n) {
    return '角色 $n';
  }

  @override
  String get charEditorContinue => '继续';

  @override
  String get charEditorParticipants => '参与者';

  @override
  String get charEditorSourceTarget => '来源 → 目标';

  @override
  String get charEditorMutual => '双向';

  @override
  String get charsSelectOrCreate => '选择或新建角色';

  @override
  String get charsSearchHint => '搜索…';

  @override
  String get charsGenerateTooltip => '生成角色';

  @override
  String get charsTextGenNeedsKey => '需要文本生成功能（请先设置 API 密钥）';

  @override
  String get charsTextGenNeedsKeyWardrobe => '需要文本生成功能（请在文本生成设置中设置 API 密钥）';

  @override
  String get charsTextGenNoPermission => '当前账号没有文本生成权限';

  @override
  String get charsNew => '新建角色';

  @override
  String get charsNewDefaultName => '新角色';

  @override
  String get charsEmptyList => '还没有角色';

  @override
  String get charsUnnamed => '（未命名）';

  @override
  String get charsGenerated => '角色已生成';

  @override
  String get charsAddedToPrompt => '已加入提示词';

  @override
  String get charsNamePlaceholder => '角色名称';

  @override
  String get charsPhotoshoot => '拍摄';

  @override
  String get charsDelete => '删除角色';

  @override
  String charsDeleteMessage(String name) {
    return '删除“$name”及其衣橱？';
  }

  @override
  String get charsGender => '性别';

  @override
  String get charsGenderUnspecified => '（未指定）';

  @override
  String get charsGenderFemale => '女性';

  @override
  String get charsGenderMale => '男性';

  @override
  String get charsGenderNonbinary => '非二元';

  @override
  String get charsTint => '着色';

  @override
  String get charsTintAccent => '强调色';

  @override
  String get charsTintAccent2 => '强调色 2';

  @override
  String get charsTintBg => '背景';

  @override
  String get charsIdentityTags => '身份标签——此处不含服装';

  @override
  String get charsBaseLabel => '基础 — 1girl/1boy、种族、年龄、永久特征';

  @override
  String get charsFaceLabel => '面部 — 眼睛颜色/形状、眉毛、鼻子、嘴唇';

  @override
  String get charsHairLabel => '头发 — 颜色、长度、发型、质感';

  @override
  String get charsBodyLabel => '身体 — 体型、比例、胸部';

  @override
  String get charsNegativeLabel => '负面 — 使用此角色时注入负面提示词';

  @override
  String get charsNsfwSection => 'NSFW 子分组（可选）';

  @override
  String get charsStyleSection => '风格标识与描述（可选）';

  @override
  String get charsSoulSection => '性格 / 灵魂（可选）';

  @override
  String get charsNsfwTop => 'nsfw 上身';

  @override
  String get charsNsfwBottom => 'nsfw 下身';

  @override
  String get charsNsfwAlways => 'nsfw 常驻';

  @override
  String get charsArtistTag => '画师标签';

  @override
  String get charsStylePrefix => '风格前缀';

  @override
  String get charsDescriptionLabel => '角色描述（自然语言；NAI 生图不使用）';

  @override
  String get charsSoulLabel => '灵魂 — 长篇性格文档（生图不使用）';

  @override
  String get charsCombinedTags => '合并标签（预览——身体 + 主服装）';

  @override
  String get charsEmptyValue => '（空）';

  @override
  String get charsWardrobe => '衣橱';

  @override
  String get charsGenerateOutfitsTooltip => '使用文本生成来生成服装';

  @override
  String get charsGenerating => '生成中…';

  @override
  String get charsGenerateOutfits => '生成服装';

  @override
  String get charsNewOutfit => '新建服装';

  @override
  String get charsNoOutfits => '还没有服装——可以添加或生成一组。';

  @override
  String get charsDeleteOutfitTitle => '删除服装';

  @override
  String charsDeleteOutfitMessage(String name) {
    return '删除“$name”？';
  }

  @override
  String get charsNewOutfitDefaultName => '新服装';

  @override
  String get charsTextGenNotConfigured => '文本生成尚未配置';

  @override
  String get charsNoOutfitsReturned => '没有返回任何服装';

  @override
  String charsOutfitsAdded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已添加 $count 套服装',
    );
    return '$_temp0';
  }

  @override
  String charsGenerationFailed(String error) {
    return '生成失败：$error';
  }

  @override
  String get charsWear => '穿上';

  @override
  String get charsState => '状态';

  @override
  String get charsSetPrimary => '设为主服装';

  @override
  String get charsEditOutfit => '编辑服装';

  @override
  String get charsOutfitName => '名称';

  @override
  String get charsOutfitNameHint => '雨天通勤风';

  @override
  String get charsClothingTags => '服装标签（4–7 件衣物）';

  @override
  String get charsNegativeTagsOptional => '负面标签（可选）';

  @override
  String get charsSeasons => '季节';

  @override
  String get charsWeatherLabel => '天气';

  @override
  String get charsActivities => '活动';

  @override
  String get charsTimeSlots => '时段';

  @override
  String charsComfortTemp(int start, int end) {
    return '舒适温度  $start°C – $end°C';
  }

  @override
  String get charsDefaultOutfitName => '服装';

  @override
  String get charsGenerateOutfitsTitle => '生成服装';

  @override
  String charsHowMany(int count) {
    return '数量：$count';
  }

  @override
  String get charsEraHint => '年代 / 场景提示（可选）';

  @override
  String get charsEraHintExample => '例如：1920 年代巴黎、平安时代的日本、近未来';

  @override
  String get charsVibeHint => '氛围提示（可选）';

  @override
  String get charsVibeHintExample => '例如：温馨学院风、哥特、海滩极简';

  @override
  String get charsGenerate => '生成';

  @override
  String get charsStateNoGarments => '此服装的标签中没有可分类的衣物。';

  @override
  String get charsOutfitState => '服装状态';

  @override
  String get charsDishevelled => '凌乱';

  @override
  String get charsResetIntact => '重置为完好';

  @override
  String get charsReparse => '从标签重新解析';

  @override
  String get charsConcealed => '被遮挡';

  @override
  String get charsRenderedTags => '渲染后的标签';

  @override
  String get charsApplyToPrompt => '应用到提示词';

  @override
  String get charsUseTheseTags => '使用这些标签';

  @override
  String get charsTopPrefix => '上';

  @override
  String get charsBottomPrefix => '下';

  @override
  String get charsGenTitle => '生成角色';

  @override
  String get charsGenVibe => '氛围（可选）';

  @override
  String get charsGenVibeHint => '描述氛围——例如“厌倦战争的老兵转行当面包师”——留空则由模型决定';

  @override
  String get charsGenGenderAny => '任意（由模型决定）';

  @override
  String get charsGenEra => '年代 / 时期';

  @override
  String get charsGenLocation => '地点（可选）';

  @override
  String get charsGenLocationHint => '例如：葡萄牙的海滨小镇、临冬城——留空则由模型决定';

  @override
  String get charsGenNsfw => 'NSFW 标签';

  @override
  String get charsGenNsfwHint => '同时生成拆分的 nsfw_* 标签分组';

  @override
  String get charsGenStyle => '风格（可选）';

  @override
  String get charsGenStyleHint => '例如：画师标签——留空则由模型决定';

  @override
  String charsGenWardrobe(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 套服装',
    );
    return '初始衣橱：$_temp0';
  }

  @override
  String get charsGenMeetNote => '另外总会生成“初见”服装。';

  @override
  String get charsGenProgressTitle => '正在生成角色';

  @override
  String get charsGenPreparing => '准备中…';

  @override
  String get charsGenProgressNote =>
      '这会调用模型多次——使用免费/Tablet 档令牌时，较长的性格描述可能需要多轮续写。';

  @override
  String get jukeboxTitle => '点唱机';

  @override
  String get jukeboxShuffleAll => '随机全部';

  @override
  String get jukeboxPlayAll => '播放全部';

  @override
  String get jukeboxNoSongPlaying => '未播放歌曲';

  @override
  String get jukeboxNowPlaying => '正在播放';

  @override
  String get jukeboxSoundFont => '音色库';

  @override
  String get jukeboxSettings => '设置';

  @override
  String get jukeboxQueueEmpty => '队列为空';

  @override
  String get jukeboxRepeat => '重复';

  @override
  String get jukeboxShuffle => '随机';

  @override
  String get jukeboxOn => '开启';

  @override
  String get jukeboxOff => '关闭';

  @override
  String get jukeboxAddToQueue => '加入队列';

  @override
  String get jukeboxMusicUnavailable => '音乐播放不可用';

  @override
  String get jukeboxDllMissing => '未找到 FluidSynth DLL';

  @override
  String get jukeboxCategoryAll => '全部';

  @override
  String get jukeboxCategoryClassical => '古典';

  @override
  String get jukeboxCategoryAnime => '动漫';

  @override
  String get jukeboxCategoryGame => '游戏';

  @override
  String get jukeboxCategoryJazz => '爵士';

  @override
  String get jukeboxCategoryAmbient => '氛围';

  @override
  String get jukeboxCategoryHoliday => '节日';

  @override
  String get jukeboxCategoryMeme => '趣味';

  @override
  String get jukeboxCategoryRock => '摇滚';

  @override
  String get mlModels => '机器学习模型';

  @override
  String get mlBgRemoval => '背景移除';

  @override
  String get mlUpscaling => '超分';

  @override
  String get mlSegmentation => '图像分割';

  @override
  String get mlDownload => '下载';

  @override
  String get mlDownloaded => '已下载';

  @override
  String get mlRetry => '重试';

  @override
  String get mlCancel => '取消';

  @override
  String get mlDelete => '删除';

  @override
  String get mlRemoveBg => '移除背景';

  @override
  String get mlUpscale => '超分';

  @override
  String get mlSegment => '分割';

  @override
  String get mlCanvas => '画布';

  @override
  String get mlSave => '保存';

  @override
  String get mlDiscard => '丢弃';

  @override
  String get mlAddPoint => '添加';

  @override
  String get mlRemovePoint => '移除';

  @override
  String get mlBack => '返回';

  @override
  String get mlEncodingImage => '正在编码图像…';

  @override
  String get mlTapToSelect => '点按图像以选择区域';

  @override
  String get mlUndoPoint => '撤销上一个点';

  @override
  String get mlClearPoints => '清除所有点';

  @override
  String mlPointCount(int count) {
    return '$count 个点';
  }

  @override
  String get mlOpacity => '不透明度';

  @override
  String get mlEdgeRefine => '边缘优化';

  @override
  String get mlThreshold => '阈值';

  @override
  String get mlFeather => '羽化';

  @override
  String get mlDone => '完成';

  @override
  String get mlUpscaleCompare => '放大对比';

  @override
  String get mlSaved => '已保存';

  @override
  String mlSavedFile(String name) {
    return '已保存：$name';
  }

  @override
  String get mlTierFast => '快速';

  @override
  String get mlTierBalanced => '平衡';

  @override
  String get mlTierBalancedShort => '平衡';

  @override
  String get mlTierQuality => '质量';

  @override
  String get mlUpscalingImages => '正在放大图像';

  @override
  String get mlUpscaleFailed => '图像放大失败';

  @override
  String get mlRecommended => '推荐';

  @override
  String get mlMayBeSlow => '可能较慢';

  @override
  String get mlNotRecommended => '不推荐';

  @override
  String get mlNotAvailableOnPlatform => '此平台不可用';

  @override
  String get mlLowRamWarning => '内存不足 — 可能崩溃';

  @override
  String get mlDesktopOnlyMayCrash => '仅限桌面端——可能崩溃';

  @override
  String get mlDownloadFailed => '下载失败';

  @override
  String get mlManagerSubtitle => '下载并管理用于背景移除和放大的本地 ML 模型。';

  @override
  String get mlNoModelsDownloaded => '尚未下载任何模型';

  @override
  String mlModelsDownloaded(int count, String size) {
    return '已下载 $count 个模型 · $size';
  }

  @override
  String get mlMobileApiNote => '在移动设备上，放大和背景移除使用 NovelAI API。本地 ML 模型仅适用于桌面端。';

  @override
  String get mlSegmentationNote => '使用 SAM 的交互式对象选择。会同时下载编码器和解码器。';

  @override
  String get mlUnknownModels => '未知模型';

  @override
  String get mlUnknownModelsNote => '旧版或无法识别的 .onnx/.ort 文件。删除可释放磁盘空间。';

  @override
  String mlDeleteModelTitle(String name) {
    return '删除 $name？';
  }

  @override
  String mlDeleteModelMessage(String size) {
    return '这将释放 $size 磁盘空间。';
  }

  @override
  String get mlRecommendedForDevice => '适合你的设备';

  @override
  String get mlSlowOnDevice => '在此设备上可能较慢';

  @override
  String get mlNaiApiUpscale => 'NOVELAI API 放大';

  @override
  String get mlNaiApiUpscaleDesc =>
      '通过 NovelAI API 在服务器端放大至 4 倍。需要 API 密钥，无需下载。';

  @override
  String get mlNaiApiBgRemoval => 'NOVELAI API 背景移除';

  @override
  String get mlNaiApiBgRemovalDesc =>
      '通过 NovelAI API 在服务器端移除背景。需要 API 密钥，无需下载。';

  @override
  String get mlCloud => '云端';

  @override
  String get mlNoApiKey => '未设置 API 密钥';

  @override
  String get mlTierQualityShort => '高质';

  @override
  String get mlDeviceMobile => '移动端';

  @override
  String get mlDeviceDesktop => '桌面端';

  @override
  String get mlDeviceBoth => '通用';

  @override
  String get mlBgRemovedAndSaved => '背景已移除并保存';

  @override
  String mlBgRemovedCount(int completed, int total) {
    return '背景已移除：$completed/$total 张图像';
  }

  @override
  String mlUpscaledCount(int completed, int total) {
    return '已放大：$completed/$total 张图像';
  }

  @override
  String mlBgRemovedSavedAs(String name) {
    return '背景已移除：保存为 $name';
  }

  @override
  String get toolsDirectorTools => '导演工具';

  @override
  String get toolsEnhance => '增强';

  @override
  String get toolDiscardResultTitle => '放弃结果？';

  @override
  String get toolDiscardResultMessage => '该结果尚未保存，返回后将被丢弃。';

  @override
  String get toolDiscardResultConfirm => '放弃';

  @override
  String get directorToolsTitle => '导演工具';

  @override
  String get directorToolsDesc => '服务器端图像处理：移除背景、提取线稿、上色等';

  @override
  String get directorToolsUseCurrent => '使用当前生成结果';

  @override
  String get directorToolsUseCurrentDesc => '以最后生成的图像作为源图';

  @override
  String get directorToolsSelectTool => '选择工具';

  @override
  String get directorToolsProcess => '处理';

  @override
  String get directorToolsProcessing => '处理中...';

  @override
  String get directorToolsDefry => '效果强度';

  @override
  String get directorToolsMood => '氛围';

  @override
  String get directorToolBgRemoval => '移除背景';

  @override
  String get directorToolLineart => '线稿';

  @override
  String get directorToolSketch => '草图';

  @override
  String get directorToolColorize => '上色';

  @override
  String get directorToolEmotion => '表情';

  @override
  String get directorToolDeclutter => '清理杂物';

  @override
  String get moodNeutral => '平静';

  @override
  String get moodHappy => '开心';

  @override
  String get moodSad => '悲伤';

  @override
  String get moodAngry => '愤怒';

  @override
  String get moodScared => '害怕';

  @override
  String get moodSurprised => '惊讶';

  @override
  String get moodTired => '疲倦';

  @override
  String get moodExcited => '激动';

  @override
  String get moodNervous => '紧张';

  @override
  String get moodThinking => '思考';

  @override
  String get moodConfused => '困惑';

  @override
  String get moodShy => '害羞';

  @override
  String get moodDisgusted => '厌恶';

  @override
  String get moodSmug => '得意';

  @override
  String get moodBored => '无聊';

  @override
  String get moodLaughing => '大笑';

  @override
  String get moodIrritated => '烦躁';

  @override
  String get moodAroused => '动情';

  @override
  String get moodEmbarrassed => '尴尬';

  @override
  String get moodWorried => '担忧';

  @override
  String get moodLove => '爱意';

  @override
  String get moodDetermined => '坚定';

  @override
  String get moodHurt => '受伤';

  @override
  String get moodPlayful => '俏皮';

  @override
  String get directorToolsPrompt => '提示词';

  @override
  String get directorToolsPromptHint => '可选：用于上色/情绪风格的提示词...';

  @override
  String get directorToolsSaved => '结果已保存到图库';

  @override
  String get enhanceTitle => '图像增强';

  @override
  String get enhanceDesc => '通过图生图重新处理并增强图像';

  @override
  String get enhanceUseCurrent => '使用当前生成结果';

  @override
  String get enhanceUseCurrentDesc => '以最后生成的图像作为源图';

  @override
  String get enhanceProcess => '增强';

  @override
  String get enhanceProcessing => '增强中...';

  @override
  String get enhancePrompt => '提示词';

  @override
  String get enhanceNegative => '负面提示词';

  @override
  String get enhanceStrength => '强度';

  @override
  String get enhanceNoise => '噪声';

  @override
  String get enhanceResolutionScale => '分辨率缩放';

  @override
  String get enhanceSaved => '增强图像已保存到图库';

  @override
  String get settingsSeedControl => '显示种子控制';

  @override
  String get settingsSeedControlDesc => '在生成界面显示种子值和随机切换';

  @override
  String get settingsShowTooltips => '显示提示';

  @override
  String get settingsShowTooltipsDesc => '悬停或长按按钮时显示帮助提示';

  @override
  String get commonMenu => '菜单';

  @override
  String get presetLoad => '加载预设';

  @override
  String get settingsStylesToggle => '切换样式';

  @override
  String get canvasLayerToggleVisibility => '切换可见性';

  @override
  String get mainRefreshAnlas => '刷新资源';

  @override
  String get enhanceSettingsTooltip => '设置';

  @override
  String get directorToolsSettingsTooltip => '设置';

  @override
  String get sidebarCollapse => '收起';

  @override
  String get sidebarExpand => '展开';

  @override
  String get naiUpscale => 'NAI 放大';

  @override
  String get naiUpscaling => '正在通过 API 放大...';

  @override
  String get naiUpscaleFailed => 'API 放大失败';

  @override
  String naiUpscaledCount(int completed, int total) {
    return 'API 已放大：$completed/$total 张图像';
  }

  @override
  String get naiApiKeyRequired => '需要 API 密钥';

  @override
  String get naiActionNotPermitted => '当前账号无权使用此操作';

  @override
  String get naiImageUnreadable => '无法读取图片尺寸';

  @override
  String get comparisonBefore => '处理前';

  @override
  String get comparisonAfter => '处理后';

  @override
  String get comparisonSideBySide => '并排对比';

  @override
  String get comparisonSliderMode => '滑动对比模式';

  @override
  String get comparisonSwap => '交换';

  @override
  String get settingsBgRemovalButton => '背景移除按钮';

  @override
  String get settingsBgRemovalButtonDesc => '在图像查看器中显示背景移除按钮';

  @override
  String get settingsUpscaleButton => '放大按钮';

  @override
  String get settingsUpscaleButtonDesc => '在图像查看器中显示放大按钮';

  @override
  String get settingsEnhanceButton => '增强按钮';

  @override
  String get settingsEnhanceButtonDesc => '在图像查看器中显示增强按钮';

  @override
  String get settingsDirectorToolsButton => '导演工具按钮';

  @override
  String get settingsDirectorToolsButtonDesc => '在图像查看器中显示导演工具按钮';

  @override
  String get settingsExportButton => '导出到设备按钮';

  @override
  String get settingsExportButtonDesc => '显示导出按钮以直接保存图片到相册';

  @override
  String get settingsAutoExport => '自动导出到设备';

  @override
  String get settingsAutoExportDesc => '自动将生成的图片保存到设备相册';

  @override
  String get settingsExportAlbum => '导出相册名称';

  @override
  String get settingsExportAlbumDesc => '导出的图片保存到的设备文件夹/相册';

  @override
  String get settingsExportFolder => '导出文件夹';

  @override
  String get settingsExportFolderDesc => '选择自定义导出文件夹（SD卡等）。设置后将覆盖相册名称。';

  @override
  String get settingsExportFolderDefault => '默认（设备相册）';

  @override
  String get quickActionEnhance => '增强';

  @override
  String get quickActionDirectorTools => '导演工具';

  @override
  String get themeColorBgRemoval => '背景移除';

  @override
  String get themeColorUpscale => '图像放大';

  @override
  String get jukeboxSynthUnavailable => '合成器不可用';

  @override
  String get jukeboxImport => '导入';

  @override
  String get jukeboxKeyboard => '键盘';

  @override
  String get jukeboxGame => '游戏';

  @override
  String get jukeboxEnd => '结束';

  @override
  String get jukeboxTempo => '速度';

  @override
  String get jukeboxKeyboardHint => '按键：A‑L  升调：W,E,T,Y,U,O,P  八度：Z/X';

  @override
  String get jukeboxGameResults => '结果';

  @override
  String get jukeboxGameScore => '得分';

  @override
  String get jukeboxGameMaxCombo => '最高连击';

  @override
  String get jukeboxGameAccuracy => '准确率';

  @override
  String get jukeboxGamePerfect => '完美';

  @override
  String get jukeboxGameGreat => '优秀';

  @override
  String get jukeboxGameGood => '良好';

  @override
  String get jukeboxGameMiss => '失误';

  @override
  String get jukeboxHighScores => '最高分';

  @override
  String jukeboxQueueCount(int count) {
    return '队列（$count）';
  }

  @override
  String get jukeboxStyle => '风格';

  @override
  String get jukeboxGameModeTooltip => '游戏模式';

  @override
  String get jukeboxEndGameTooltip => '结束游戏';

  @override
  String get jukeboxImportTooltip => '导入';

  @override
  String get jukeboxShuffleAllTooltip => '随机播放全部';

  @override
  String get jukeboxPlayAllTooltip => '播放全部';

  @override
  String get jukeboxKeyboardTooltip => '键盘';

  @override
  String get jukeboxGameMode => '游戏模式';

  @override
  String get jukeboxNoSongs => '暂无歌曲';

  @override
  String get jukeboxRecommendedBadge => '推荐';

  @override
  String get jukeboxAnalyzing => '分析中...';

  @override
  String get jukeboxNoScoresYet => '暂无成绩';

  @override
  String get jukeboxSelectInstrument => '选择乐器';

  @override
  String get jukeboxPlayGame => '开始游戏';

  @override
  String jukeboxChannelLabel(int channel) {
    return '通道 $channel';
  }

  @override
  String jukeboxCombo(int count) {
    return '$count 连击';
  }

  @override
  String get jukeboxPressOnTheLine => '在线条处按下';

  @override
  String get jukeboxGradePerfect => '完美';

  @override
  String get jukeboxGradeGreat => '优秀';

  @override
  String get jukeboxGradeGood => '良好';

  @override
  String get jukeboxGradeMiss => '失误';

  @override
  String get jukeboxDifficultyEasy => '简单';

  @override
  String get jukeboxDifficultyMedium => '中等';

  @override
  String get jukeboxDifficultyHard => '困难';

  @override
  String get jukeboxDifficultyExtreme => '极限';

  @override
  String get jukeboxInstrumentAcousticGrandPiano => '三角钢琴';

  @override
  String get jukeboxInstrumentElectricPiano => '电钢琴';

  @override
  String get jukeboxInstrumentHarpsichord => '大键琴';

  @override
  String get jukeboxInstrumentVibraphone => '颤音琴';

  @override
  String get jukeboxInstrumentXylophone => '木琴';

  @override
  String get jukeboxInstrumentChurchOrgan => '教堂管风琴';

  @override
  String get jukeboxInstrumentNylonGuitar => '尼龙弦吉他';

  @override
  String get jukeboxInstrumentSteelGuitar => '钢弦吉他';

  @override
  String get jukeboxInstrumentCleanElectricGuitar => '清音电吉他';

  @override
  String get jukeboxInstrumentDistortionGuitar => '失真电吉他';

  @override
  String get jukeboxInstrumentAcousticBass => '原声贝斯';

  @override
  String get jukeboxInstrumentElectricBassFinger => '指弹电贝斯';

  @override
  String get jukeboxInstrumentViolin => '小提琴';

  @override
  String get jukeboxInstrumentCello => '大提琴';

  @override
  String get jukeboxInstrumentOrchestralHarp => '管弦乐竖琴';

  @override
  String get jukeboxInstrumentStringEnsemble => '弦乐合奏';

  @override
  String get jukeboxInstrumentTrumpet => '小号';

  @override
  String get jukeboxInstrumentFrenchHorn => '圆号';

  @override
  String get jukeboxInstrumentAltoSax => '中音萨克斯';

  @override
  String get jukeboxInstrumentFlute => '长笛';

  @override
  String get jukeboxInstrumentSquareLeadSynth => '方波合成主音';

  @override
  String get jukeboxInstrumentLeadVoice => '人声主音';

  @override
  String get jukeboxKaraokeBadge => '卡拉OK';

  @override
  String get jukeboxDeleteCustomSongTooltip => '删除自定义歌曲';

  @override
  String get jukeboxDeleteSong => '删除歌曲';

  @override
  String jukeboxDeleteSongConfirm(String title) {
    return '删除 $title？此操作将从磁盘移除文件。';
  }

  @override
  String get jukeboxStyleHighlight => '高亮';

  @override
  String get jukeboxStyleUpcoming => '即将播放';

  @override
  String get jukeboxStyleNextLine => '下一行';

  @override
  String get jukeboxStyleGlow => '发光';

  @override
  String get jukeboxVisualizer => '频谱可视化';

  @override
  String get jukeboxToggleVisualizer => '切换可视化显示';

  @override
  String get jukeboxPrevious => '上一首';

  @override
  String get jukeboxNext => '下一首';

  @override
  String get jukeboxPlay => '播放';

  @override
  String get jukeboxPause => '暂停';

  @override
  String get jukeboxMute => '静音';

  @override
  String get jukeboxUnmute => '取消静音';

  @override
  String get jukeboxRemoveFromQueue => '从队列移除';

  @override
  String get jukeboxFullscreen => '全屏';

  @override
  String get jukeboxKaraokeLabel => '卡拉 OK';

  @override
  String get jukeboxBundled => '内置';

  @override
  String get jukeboxSoundfontDownload => '下载';

  @override
  String get jukeboxSoundfontDelete => '删除音色库';

  @override
  String get jukeboxSoundfontDeleteTitle => '删除音色库';

  @override
  String jukeboxSoundfontDeleteMessage(String name) {
    return '删除 $name？之后可以重新下载。';
  }

  @override
  String get jukeboxVizIntensity => '强度';

  @override
  String get jukeboxVizSpeed => '速度';

  @override
  String get jukeboxVizDensity => '密度';

  @override
  String get jukeboxFontSize => '字号';

  @override
  String get jukeboxResetToDefaults => '恢复默认';

  @override
  String jukeboxRepeatMode(String mode) {
    return '循环：$mode';
  }

  @override
  String jukeboxShuffleStatus(String status) {
    return '随机：$status';
  }

  @override
  String get galleryBadgeNaiUpscale => 'NAI 放大';

  @override
  String galleryBadgeDirectorTool(String tool) {
    return '导演：$tool';
  }

  @override
  String get galleryBadgeEnhanced => '已增强';

  @override
  String get galleryBadgeBgRemoved => '已去背景';

  @override
  String get galleryBadgeUpscaled => '已放大';

  @override
  String get galleryBgRemovalFailed => '背景移除失败';

  @override
  String get galleryRemovingBackgrounds => '正在去除背景';

  @override
  String naiUpscaleTooLarge(int width, int height) {
    return '图像过大，无法使用 NAI 放大（${width}x$height 超出单边 2048px 限制）';
  }

  @override
  String get naiRemovingBackground => '正在移除背景...';

  @override
  String get naiBgRemovalFailed => 'NAI 背景移除失败';

  @override
  String get directorToolsFromGallery => '来自图库';

  @override
  String get importDialogTitle => '导入元数据';

  @override
  String get importCategoryPrompt => '提示词';

  @override
  String get importCategoryNegative => '负面提示词';

  @override
  String get importCategoryCharacters => '角色';

  @override
  String get importCategorySeed => '种子';

  @override
  String get importCategoryStyles => '样式';

  @override
  String get importCategorySettings => '设置（分辨率、采样器、缩放）';

  @override
  String get importActionImport => '导入';

  @override
  String get importNothingAvailable => '未找到可导入的元数据';

  @override
  String get importStylesAutoDetected => '从提示词自动检测';

  @override
  String get importStylesEmbedded => '建议关闭 - 已嵌入提示词';

  @override
  String get img2imgOutputRes => '输出分辨率';

  @override
  String get duplicateImageWarning => '生成的图像与上次完全相同——请尝试更换种子或检查氛围迁移/参考图';

  @override
  String get duplicateImageRandomize => '随机化';

  @override
  String get generationNoParametersVaried => '参数没有变化，请检查 Seed。';

  @override
  String get generationRandomizeSeed => '随机 Seed';

  @override
  String get settingsCredits => '制作人员';

  @override
  String get settingsSpecialThanks => '特别感谢';

  @override
  String get settingsAnonTesters => '……以及所有匿名测试人员';

  @override
  String get settingsLayoutMode => '布局模式';

  @override
  String get settingsLayoutModeDesc => '控制宽屏上设置面板的显示方式';

  @override
  String get settingsLayoutAuto => '自动';

  @override
  String get settingsLayoutSidebar => '侧边栏';

  @override
  String get settingsLayoutClassic => '经典';

  @override
  String get settingsPromptPosition => '提示词位置';

  @override
  String get settingsPromptPositionDesc => '侧边栏模式下提示词输入的位置';

  @override
  String get settingsPromptLeft => '左侧';

  @override
  String get settingsPromptRight => '右侧';

  @override
  String get settingsSidebarWidth => '侧栏宽度';

  @override
  String get settingsSidebarWidthDesc => '选择紧凑模式以获得更窄的侧栏面板';

  @override
  String get settingsSidebarCompact => '紧凑';

  @override
  String get settingsSidebarNormal => '标准';

  @override
  String get toolsTextGen => '文本生成';

  @override
  String get textGenTitle => '文本生成';

  @override
  String get textGenInput => '输入';

  @override
  String get textGenInputHint => '要续写的文本……';

  @override
  String get textGenInputNote => 'NovelAI 文本模型会续写你的文本，而不是按聊天回合工作。';

  @override
  String get textGenModel => '模型';

  @override
  String get textGenModelCustom => '自定义……';

  @override
  String get textGenParameters => '参数';

  @override
  String get textGenPreset => '预设';

  @override
  String get textGenTemperature => 'Temperature';

  @override
  String get textGenMaxLength => '最大长度';

  @override
  String get textGenTopP => 'Top P';

  @override
  String get textGenTopK => 'Top K';

  @override
  String get textGenRepetitionPenalty => '重复惩罚';

  @override
  String get textGenPhraseRepPen => '短语重复惩罚';

  @override
  String get textGenGenerateUntilSentence => '生成到句末';

  @override
  String get textGenStopStrings => '停止字符串';

  @override
  String get textGenStopStringsNote => '每行一个。在第一个匹配处截断输出（客户端）。';

  @override
  String get textGenStopStringsHint => '例如对话的结束行';

  @override
  String get textGenGenerate => '生成';

  @override
  String get textGenCancel => '取消';

  @override
  String get textGenContinue => '继续';

  @override
  String get textGenCopy => '复制';

  @override
  String get textGenClear => '清除';

  @override
  String get textGenCopied => '已复制到剪贴板';

  @override
  String get textGenOutput => '输出';

  @override
  String get textGenOutputEmpty => '生成的文本将显示在这里。';

  @override
  String get textGenErrNoToken => '尚未设置 NovelAI 令牌，请在设置中添加。';

  @override
  String get textGenErrEmptyInput => '请输入要续写的文本。';

  @override
  String get textGenClearConfirmTitle => '清除输出？';

  @override
  String get textGenClearConfirmMessage => '生成的文本及其推理内容将被移除。如需保留，请先复制。';

  @override
  String get textGenHistory => '历史';

  @override
  String get textGenEnableThinking => '启用思考';

  @override
  String get textGenEnableThinkingNote => 'GLM 会在回答前生成一段推理。会强制使用非流式响应。';

  @override
  String get textGenReasoning => '推理';

  @override
  String get serverHistoryTitle => '服务器历史';

  @override
  String get serverHistoryAllUsers => '全部用户';

  @override
  String get serverHistoryRefresh => '刷新';

  @override
  String get serverHistoryEmpty => '还没有服务器历史';

  @override
  String get serverHistoryImportParameters => '导入参数';

  @override
  String get serverHistoryImportSuccess => '已导入参数';

  @override
  String get serverHistoryDownload => '下载';

  @override
  String get serverHistoryDeleteConfirm => '从你的历史中隐藏这条记录。';

  @override
  String get serverHistoryBatchImportParameters => '导入本组参数';

  @override
  String get serverHistoryBatchImportSuccess => '已导入本组参数';

  @override
  String get serverHistoryBatchDownload => '下载整组';

  @override
  String get serverHistoryBatchDelete => '删除整组';

  @override
  String get serverHistoryBatchDeleteConfirm => '从你的历史中隐藏这一组的全部图片？';

  @override
  String serverHistoryDeleteFailed(String error) {
    return '删除失败：$error';
  }

  @override
  String get serverHistoryDeleteActive => '仍在排队或生成中，完成后才能删除。';

  @override
  String serverHistoryLoadFailed(String error) {
    return '无法加载历史：$error';
  }

  @override
  String get serverHistoryRetry => '重试';

  @override
  String get serverHistoryUsersUnavailable => '无法加载用户列表，用户筛选暂不可用。';

  @override
  String get serverHistoryItemCancelled => '任务已取消，没有扣费。';

  @override
  String quotePointsTooltipFree(int points) {
    return '免费 · $points 绿点';
  }

  @override
  String quotePointsTooltipPaid(int points) {
    return '付费 · $points 红点';
  }

  @override
  String quoteDiscountNote(int percent) {
    return '绿点折扣：$percent%';
  }

  @override
  String get quoteInvalidBadge => '参数无效';

  @override
  String quoteInvalidTooltip(String field) {
    return '当前参数超出服务端允许的范围（$field）。';
  }

  @override
  String get quoteReasonSizeNotFree => '分辨率不在免费尺寸内';

  @override
  String get quoteReasonStepsOverFreeLimit => '步数超过免费上限';

  @override
  String get quoteReasonSmea => '启用了 SMEA';

  @override
  String get quoteReasonImageInput => '含图片输入（图生图 / 局部重绘）';

  @override
  String get quoteReasonDirectorRefs => '包含精确参考图';

  @override
  String get quoteReasonVibes => '包含氛围迁移';

  @override
  String get quoteReasonAllowanceExhausted => '免费额度暂时用尽';

  @override
  String get quoteReasonPaidTool => '付费工具';

  @override
  String get quoteAdjustToFree => '改为免费';

  @override
  String get quoteAdjustToFreeTooltip => '把尺寸、步数和 SMEA 改回免费范围';

  @override
  String get quoteFreeOnlyNotice => '当前账号只能免费生成，以下设置会消耗红点：';

  @override
  String get quoteFreeAllowanceUnavailable => '免费额度暂时用尽，暂时无法免费生成。';

  @override
  String get quoteAdjustToFreeAction => '调整为免费参数';

  @override
  String get quoteConfirmTitle => '价格有变化';

  @override
  String quoteConfirmPriceRed(int points) {
    return '价格以服务端为准：$points 红点。';
  }

  @override
  String quoteConfirmPriceGreen(int points) {
    return '价格以服务端为准：$points 绿点。';
  }

  @override
  String quoteConfirmShown(int points) {
    return '之前显示的价格是 $points 点。';
  }

  @override
  String get quoteConfirmReasonAllowance => '免费额度暂时用尽，这次改用红点计费。';

  @override
  String get quoteConfirmReasonOther => '显示价格之后，价格或账号状态发生了变化。';

  @override
  String get quoteConfirmContinue => '按此价格继续';

  @override
  String generationInputsActive(int references, int vibes) {
    return '参考图 $references · 氛围迁移 $vibes';
  }

  @override
  String generationInputsPaused(int count) {
    return '$count 个已暂停';
  }

  @override
  String get generationInputsTooltip => '下一张图会带上的参考图和氛围迁移。点击打开。';

  @override
  String get refPausedNoRedPoints => '已暂停：红点不足，不会发送。';

  @override
  String get refPausedNoPermission => '已暂停：当前账号不能使用付费点数生成，不会发送。';

  @override
  String refAccessCountRefs(int count) {
    return '$count 张参考图';
  }

  @override
  String refAccessCountVibes(int count) {
    return '$count 个氛围迁移';
  }

  @override
  String get refAccessSeparator => '、';

  @override
  String refAccessPausedNoRedPoints(String items) {
    return '红点不足：$items已暂停，不会发送';
  }

  @override
  String refAccessPausedNoPermission(String items) {
    return '没有付费生成权限：$items已暂停，不会发送';
  }

  @override
  String refAccessResumed(String items) {
    return '付费点数已恢复：$items将重新发送';
  }

  @override
  String toolMaxRedPoints(int points) {
    return '最多 $points 红点';
  }

  @override
  String get generationBusy => '已有生成正在进行，请等待完成。';

  @override
  String get generationFailedFallback => '生成失败';

  @override
  String get generationSeedInvalid => '种子必须是 0 到 4294967295 之间的整数。';

  @override
  String get generationDropToImport => '拖放以导入设置';

  @override
  String get generationCancelQueued => '取消排队';

  @override
  String get generationResumeWatching => '继续等待';

  @override
  String get generationWatchTimedOut => '已停止等待服务器。图片可能仍会完成，可点击继续等待再次检查。';

  @override
  String get generationItemCancelled => '已在开始前取消';

  @override
  String get generationReuseSeed => '复用种子';

  @override
  String get photoshootTitle => '摄影棚';

  @override
  String get photoshootCharacterNotFound => '找不到角色';

  @override
  String get photoshootNoOutfit => '（无服装）';

  @override
  String get photoshootPreviewPlaceholder => '生成的照片会显示在这里';

  @override
  String get photoshootTapToView => '点击查看';

  @override
  String get photoshootTabDress => '服装';

  @override
  String get photoshootTabScene => '场景';

  @override
  String get photoshootTabPrompt => '提示词';

  @override
  String get photoshootNoOutfitHint => '没有可穿戴的服装——请在角色编辑器中添加。';

  @override
  String get photoshootSaveState => '保存状态到服装';

  @override
  String get photoshootOutfitStateSaved => '服装状态已保存';

  @override
  String get photoshootSectionStyle => '风格';

  @override
  String get photoshootSectionPose => '姿势';

  @override
  String get photoshootSectionEnvironment => '环境';

  @override
  String get photoshootCustomPoseHint => '自定义姿势标签…';

  @override
  String get photoshootCustomEnvHint => '自定义环境标签…';

  @override
  String photoshootSelectedCount(int count) {
    return '已选 $count 项';
  }

  @override
  String get photoshootClear => '清除';

  @override
  String get photoshootNoPresets => '没有可用的预设';

  @override
  String get photoshootAssembledPrompt => '组装后的提示词';

  @override
  String photoshootTagCount(int count) {
    return '$count 个标签';
  }

  @override
  String get photoshootEmptyPrompt => '（空）';

  @override
  String get photoshootPromptBuiltFrom =>
      '组装顺序：风格 → 身体 → 服装 → 姿势 → 环境。可在「服装」和「场景」标签页中调整。';

  @override
  String get photoshootGenerate => '生成';

  @override
  String get photoshootGenerating => '生成中…';

  @override
  String get photoshootSend => '发送';

  @override
  String get photoshootSentToMain => '已发送到主提示词';

  @override
  String get photoshootGenerated => '已生成';

  @override
  String photoshootGenerationFailed(String reason) {
    return '生成失败：$reason';
  }

  @override
  String get photoshootSelectOutfit => '服装';

  @override
  String get photoshootStyleCharacterDefault => '角色默认';

  @override
  String get photoshootStyleAnime => '动漫';

  @override
  String get photoshootStylePainterly => '绘画感';

  @override
  String get photoshootStylePhotoreal => '照片写实';

  @override
  String get photoshootStyleSketch => '素描';

  @override
  String get photoshootStyleWatercolor => '水彩';

  @override
  String get photoshootStyleInk => '墨水';

  @override
  String get cascadeHelpTitle => '分镜指南';

  @override
  String get cascadeHelpOverviewHeader => '概览';

  @override
  String get cascadeHelpOverviewBody =>
      '分镜用于生成角色保持一致的多镜头场景序列。每个镜头对应一次生成，拥有各自的环境、角色姿态和设置。角色外观只需在角色分配页设置一次，即可应用到所有镜头。';

  @override
  String get cascadeHelpSetupHeader => '设置流程';

  @override
  String get cascadeHelpStepCreate => '创建';

  @override
  String get cascadeHelpStepCreateDesc => '设置名称、角色数量（0-5）和定位模式';

  @override
  String get cascadeHelpStepEdit => '编辑镜头';

  @override
  String get cascadeHelpStepEditDesc => '为每个镜头设置场景/动作、环境、角色提示词、动作、位置、风格和参数';

  @override
  String get cascadeHelpStepCast => '分配角色';

  @override
  String get cascadeHelpStepCastDesc => '保存并返回主界面的播放视图';

  @override
  String get cascadeHelpStepGenerate => '生成';

  @override
  String get cascadeHelpStepGenerateDesc => '填写角色外观和可选的全局注入内容，然后逐个生成镜头';

  @override
  String get cascadeHelpBasePromptHeader => '基础提示词';

  @override
  String get cascadeHelpScene => '场景 / 动作';

  @override
  String get cascadeHelpSceneDesc =>
      '基础提示词中描述正在发生什么、如何取景的标签（例如 \"2girls, hugging, wide shot, from above\"）。人数、动作和镜头类标签放在这里。';

  @override
  String get cascadeHelpEnvironment => '环境';

  @override
  String get cascadeHelpEnvironmentDesc =>
      '基础提示词中描述场景发生地点的标签（例如 \"forest, night, indoors\"）。';

  @override
  String get cascadeHelpBasePromptNote =>
      '两者都是标签（而非自然语言），会合并进同一个基础提示词：场景 / 动作在前，环境在后。';

  @override
  String get cascadeHelpSlotsHeader => '角色槽位';

  @override
  String get cascadeHelpSlotPositive => '正向提示词';

  @override
  String get cascadeHelpSlotPositiveDesc => '每个镜头的角色标签（例如 \"happy, sitting\"）';

  @override
  String get cascadeHelpSlotNegative => '负向提示词';

  @override
  String get cascadeHelpSlotNegativeDesc => '该角色在每个镜头中不希望出现的内容';

  @override
  String get cascadeHelpSlotGrid => '位置网格';

  @override
  String get cascadeHelpSlotGridDesc => '5x5 网格，用于精确定位（需开启手动定位）';

  @override
  String get cascadeHelpSlotActions => '动作标签';

  @override
  String get cascadeHelpSlotActionsDesc => '设置该镜头中角色之间的互动';

  @override
  String get cascadeHelpActionsHeader => '动作互动';

  @override
  String get cascadeHelpActionsIntro => '点击角色槽位之间的链接图标，即可为该镜头设置互动。';

  @override
  String get cascadeHelpSourceTarget => '发起者 → 对象';

  @override
  String get cascadeHelpSourceTargetDesc => '有方向的动作（例如 A 拥抱 B）';

  @override
  String get cascadeHelpMutual => '相互 ↔';

  @override
  String get cascadeHelpMutualDesc => '双方对等参与的动作（例如牵手）';

  @override
  String get cascadeHelpActionsNote =>
      '标签会以 source#action、target#action 或 mutual#action 的形式嵌入角色提示词。';

  @override
  String get cascadeHelpCastingHeader => '角色分配页';

  @override
  String get cascadeHelpCastAppearance => '角色外观';

  @override
  String get cascadeHelpCastAppearanceDesc =>
      '每个角色的基础外观（例如 \"1girl, blue hair\"），所有镜头共用';

  @override
  String get cascadeHelpCastGlobalScene => '全局场景';

  @override
  String get cascadeHelpCastGlobalSceneDesc =>
      '应用到每个镜头的场景/动作标签（例如 \"2girls, school uniform\"），排在各镜头自己的场景 / 动作标签之前';

  @override
  String get cascadeHelpCastInjection => '全局注入';

  @override
  String get cascadeHelpCastInjectionDesc => '附加到每个镜头的额外提示词或风格';

  @override
  String get cascadeHelpCastThumbs => '镜头缩略图';

  @override
  String get cascadeHelpCastThumbsDesc => '点击选择；生成后显示预览';

  @override
  String get cascadeHelpCastCaption => '旁白字幕';

  @override
  String get cascadeHelpCastCaptionDesc =>
      '显示在镜头预览上的自由文本旁白（仅用于显示），是自然语言而非标签。可用眼睛图标切换显示。不会随分镜一起保存。';

  @override
  String get cascadeHelpCastExport => '导出';

  @override
  String get cascadeHelpCastExportDesc =>
      '将字幕烧录进单个镜头的 PNG，或把所有已生成的镜头拼成纵向/横向故事板长图（分享图标）';

  @override
  String get cascadeHelpCastGenerate => '生成';

  @override
  String get cascadeHelpCastGenerateDesc => '生成当前选中的镜头，并自动跳到下一个';

  @override
  String get cascadeHelpPerBeatHeader => '单镜头设置';

  @override
  String get cascadeHelpPerBeatBody =>
      '每个镜头可以有自己的分辨率、采样器、步数、引导强度和风格。风格从你的风格库中按镜头单独开关。';

  @override
  String get cascadeHelpTipsHeader => '小技巧';

  @override
  String get cascadeHelpTip1 => '镜头之间换场景时，修改环境标签';

  @override
  String get cascadeHelpTip2 => '在角色分配页保持角色外观一致';

  @override
  String get cascadeHelpTip3 => '按镜头修改动作标签，展现互动的变化';

  @override
  String get cascadeHelpTip4 => '复制镜头，可快速迭代相似的场景';

  @override
  String get cascadeHelpTip5 => '每个镜头可使用不同风格来营造不同氛围';

  @override
  String get canvasHelpToolsHeader => '工具';

  @override
  String get canvasHelpPaint => '画笔 — 自由绘制';

  @override
  String get canvasHelpErase => '擦除 — 擦掉笔触';

  @override
  String get canvasHelpLine => '直线 — 绘制直线';

  @override
  String get canvasHelpRectangle => '矩形 — 空心或实心';

  @override
  String get canvasHelpCircle => '圆形 / 椭圆';

  @override
  String get canvasHelpFill => '填充 — 区域填色';

  @override
  String get canvasHelpText => '文字 — 在画布上添加文字';

  @override
  String get canvasHelpEyedropper => '取色 — 吸取颜色';

  @override
  String get canvasHelpTransform => '移动 — 移动/缩放图层';

  @override
  String get canvasHelpSelect => '选区 — 矩形选择';

  @override
  String get canvasHelpLasso => '套索 — 自由选择';

  @override
  String get canvasHelpBlur => '模糊 — 高斯模糊笔刷';

  @override
  String get canvasHelpClone => '仿制图章 — 从源点复制';

  @override
  String get canvasHelpNavigationHeader => '视图操作';

  @override
  String get canvasHelpKeySpaceDrag => '空格 + 拖动';

  @override
  String get canvasHelpPan => '平移画布';

  @override
  String get canvasHelpKeyScroll => '滚轮';

  @override
  String get canvasHelpZoom => '放大 / 缩小';

  @override
  String get canvasHelpKeyCtrlScroll => 'Ctrl + 滚轮';

  @override
  String get canvasHelpBrushSize => '调整笔刷大小';

  @override
  String get canvasHelpBrushStep => '减小 / 增大笔刷';

  @override
  String get canvasHelpActionsHeader => '操作';

  @override
  String get canvasHelpKeyEscape => 'Esc';

  @override
  String get canvasHelpCancelSelection => '取消选区';

  @override
  String get canvasHelpKeyAltClick => 'Alt + 点击';

  @override
  String get canvasHelpSetCloneSource => '设置仿制图章源点';

  @override
  String get canvasHelpModesHeader => '模式';

  @override
  String get canvasHelpModeSelect => '选区';

  @override
  String get canvasHelpModeSelectDesc => '矩形选区，通过角点手柄进行移动、旋转和缩放。';

  @override
  String get canvasHelpModeLasso => '套索';

  @override
  String get canvasHelpModeLassoDesc => '自由绘制的选区路径，带有外框手柄。';

  @override
  String get canvasHelpModeBlur => '模糊';

  @override
  String get canvasHelpModeBlurDesc => '应用高斯模糊，通过大小滑块调整 sigma。';

  @override
  String get canvasHelpModeClone => '仿制图章';

  @override
  String get canvasHelpModeCloneDesc => '从源点复制像素。先按 Alt+点击设置源点，再进行绘制。';

  @override
  String get canvasHelpModeSmooth => '平滑';

  @override
  String get canvasHelpModeSmoothDesc => '在工具栏中开启后，笔触将带抗锯齿。';

  @override
  String get commonApply => '应用';

  @override
  String get commonDefault => '默认';

  @override
  String get pinUnlockButton => '解锁';

  @override
  String pinLockoutMessage(int seconds) {
    return '尝试次数过多，请 $seconds 秒后重试';
  }

  @override
  String get pinBiometricUnlock => '生物识别解锁';

  @override
  String get pinUnlockReason => '解锁 NAIWeaver';

  @override
  String get jukeboxPlayerVolume => '玩家音量';

  @override
  String get jukeboxCategoryCustom => '自定义';

  @override
  String galleryShareFailed(String error) {
    return '分享失败：$error';
  }

  @override
  String get gallerySdCard => 'SD卡';

  @override
  String get canvasQuick => '常用';

  @override
  String get canvasReset => '重置';

  @override
  String get canvasPalette => '调色板';

  @override
  String get canvasRecent => '最近';

  @override
  String get canvasResizeTitle => '调整画布大小';

  @override
  String get canvasAnchor => '锚点';

  @override
  String get helpShortcutKeyHoldTap => '长按';

  @override
  String get helpShortcutKeyDragDrop => '拖放 PNG';

  @override
  String get charsDress => '服装';

  @override
  String get tagSuggestHonorOutfitState => '遵循服装状态';

  @override
  String charEditorSheetTitle(int n) {
    return '角色 $n 编辑器';
  }

  @override
  String get charEditorNameOptional => '名称（可选）';

  @override
  String get charEditorCharacterPrompt => '角色提示词';

  @override
  String get charEditorEnterTags => '输入标签';

  @override
  String get charEditorCharacterUc => '角色负面词 (UC)';

  @override
  String get charEditorPositionGrid => '位置（5x5 网格）';

  @override
  String get charEditorSaveCharacter => '保存角色';

  @override
  String get interactionEditorTitle => '互动编辑器';

  @override
  String get interactionActionLabel => '动作';

  @override
  String get interactionActionHint => '输入动作（例如 hugging）';

  @override
  String get interactionDirectionLabel => '方向';

  @override
  String get interactionSave => '保存互动';

  @override
  String tagLibPreviewSummary(
    String prompt,
    int width,
    int height,
    int steps,
    String scale,
  ) {
    return 'P: $prompt | ${width}X$height | 步数: $steps | 缩放: $scale';
  }

  @override
  String panelSectionError(String id, String error) {
    return '$id 出错：$error';
  }

  @override
  String get mlStageStarting => '正在开始...';

  @override
  String get mlStagePreprocessing => '正在预处理...';

  @override
  String get mlStageAnalyzing => '正在分析图像...';

  @override
  String get mlStageLoadingModel => '正在加载模型...';

  @override
  String get mlStageLoadingEncoder => '正在加载编码器...';

  @override
  String get mlStageEncodingImage => '正在编码图像...';

  @override
  String get mlStageRunningInference => '正在推理...';

  @override
  String get mlStageGeneratingMatte => '正在生成蒙版（matte）...';

  @override
  String get mlStageGeneratingMask => '正在生成蒙版...';

  @override
  String get mlStageApplyingMask => '正在应用蒙版...';

  @override
  String get mlStageSplittingTiles => '正在切分图块...';

  @override
  String get mlStageUpscalingTiles => '正在放大图块...';

  @override
  String get mlStageRecombiningAlpha => '正在合并透明通道...';

  @override
  String get mlStageStitching => '正在拼接结果...';

  @override
  String get mlStageComplete => '完成';

  @override
  String get mlCpuOnly => '仅 CPU';

  @override
  String get mlSegmentEncodeFailed => '图像编码失败——请确认已下载分割模型';

  @override
  String get mlSegmentNotEncoded => '图像尚未编码——请重新打开分割工具';

  @override
  String get mlSegmentFailed => '分割失败——请换几个点再试';

  @override
  String get charsGenStepCreating => '正在创建角色…';

  @override
  String get charsGenStepWardrobe => '正在生成衣橱…';

  @override
  String get charsGenStepSaving => '正在保存…';

  @override
  String get charsGenStepDone => '完成';

  @override
  String get charsGenErrUnusable =>
      '模型没有返回可用的角色 JSON。请重试，或换用更高等级的账号 / 更大的输出长度。';

  @override
  String canvasLayerNameN(int n) {
    return '图层 $n';
  }

  @override
  String canvasImageLayerNameN(int n) {
    return '图片 $n';
  }

  @override
  String canvasLayerCopyName(String name) {
    return '$name 副本';
  }

  @override
  String get canvasSegmentedLayerName => '分割结果';

  @override
  String commonCopyName(String name) {
    return '$name（副本）';
  }

  @override
  String get packDefaultExportName => '我的资源包';

  @override
  String slideshowDefaultName(int n) {
    return '幻灯片 $n';
  }

  @override
  String get mlModelDescIsnetAnime => '二值蒙版，针对动漫优化';

  @override
  String get mlModelDescRmbgQuantized => 'Alpha 蒙版，量化版';

  @override
  String get mlModelDescRmbgBest => 'Alpha 蒙版，最佳画质';

  @override
  String get mlModelDescUpscaleFast => '2 倍放大，快速且小巧';

  @override
  String get mlModelDescUpscaleMobile => '2 倍放大，移动端备选';

  @override
  String get mlModelDescUpscaleBest => '2 倍放大，最佳画质';

  @override
  String get mlModelDescSamEncoder => '交互式分割的图像编码器';

  @override
  String get mlModelDescSamDecoder => '交互式分割的蒙版解码器';

  @override
  String get soundfontDescNes => '8 位复古 NES 音色';

  @override
  String get soundfontDescGeneralUser => '高品质 General MIDI 音色库';

  @override
  String get soundfontDescCat => '所有乐器都是猫叫声';

  @override
  String get soundfontDescSnes => '16 位超级任天堂音色';

  @override
  String get soundfontDescGenesis => '世嘉 Genesis YM2612 FM 合成器';

  @override
  String get soundfontDescN64Roxie => '任天堂 64 游戏采样';

  @override
  String get soundfontDescN64Sdk => '任天堂 64 SDK 默认采样';

  @override
  String get mlDownloadHashMismatch => '哈希校验失败';
}
