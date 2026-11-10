# Windows AI features and preinstalled extras: checklist first, nothing changes without consent.
_APP_WHY = ("Windows does not depend on this app. It is removed for every user and can be put back from the Microsoft Store.",
            "لا يعتمد Windows على هذا التطبيق. يُزال لكل المستخدمين ويمكن إعادته من Microsoft Store.")

def _app(key, en, ar, warn=None):
    rows = [(f"tweak.apps.{key}.title", f"Remove {en}", f"إزالة {ar}"), (f"tweak.apps.{key}.why", _APP_WHY[0], _APP_WHY[1])]
    if warn:
        rows.append((f"tweak.apps.{key}.warning", warn[0], warn[1]))
    return rows

S = [
("tweak.found.title", "Windows AI and extras found on this PC", "ميزات الذكاء الاصطناعي والإضافات الموجودة على هذا الجهاز"),
("tweak.found.body", "This is only a list. Nothing has been changed. These are the AI features and preinstalled extras that are present, or not yet switched off, and that Windows does not depend on. Most use little while idle, so the gain is mostly less clutter, less background activity and less data sharing; measure on the Performance page if you want numbers. Tick what you want gone, then press Apply selected: you will see every exact change and must confirm before anything happens.",
 "هذه قائمة فقط. لم يتغيّر أي شيء. هذه ميزات الذكاء الاصطناعي والإضافات المثبّتة مسبقاً الموجودة أو التي لم تُوقَف بعد والتي لا يعتمد عليها Windows. معظمها يستهلك القليل عند الخمول، فالفائدة غالباً فوضى أقل ونشاط خلفي أقل ومشاركة بيانات أقل؛ قِس من صفحة الأداء إن أردت أرقاماً. حدّد ما تريد إزالته ثم اضغط «تطبيق المحدد»: سترى كل تغيير بدقة ويجب أن تؤكد قبل حدوث أي شيء."),
("tweak.found.none", "No Windows AI features or removable extras from the list were found on this PC.", "لم يُعثر على ميزات ذكاء اصطناعي أو إضافات قابلة للإزالة من القائمة على هذا الجهاز."),
("tweak.found.count", "{0} found", "عُثر على {0}"),
("tweak.found.tick", "Tick everything in this list", "تحديد كل ما في هذه القائمة"),
("tweak.found.ticked", "{0} ticked. Nothing has changed yet: press Apply selected to review and confirm. {1} Advanced items were left out; tick those one by one after reading their tradeoff.",
 "تم تحديد {0}. لم يتغيّر شيء بعد: اضغط «تطبيق المحدد» للمراجعة والتأكيد. تُرك {1} من العناصر المتقدمة؛ حدّدها واحداً واحداً بعد قراءة مقايضتها."),
("tweak.found.never", "Never on this list: Windows Update, Microsoft Defender, the Microsoft Store, Edge, WebView2 and anything Windows needs to run.",
 "لن يظهر في هذه القائمة أبداً: Windows Update وMicrosoft Defender وMicrosoft Store وEdge وWebView2 وكل ما يحتاجه Windows ليعمل."),

("tweak.ai.copilotButton.title", "Hide the Copilot button on the taskbar", "إخفاء زر Copilot من شريط المهام"),
("tweak.ai.copilotButton.why", "Removes the Copilot button from the taskbar for your account. Same as the switch in Settings > Personalization > Taskbar.", "يزيل زر Copilot من شريط المهام لحسابك. مثل المفتاح في الإعدادات > التخصيص > شريط المهام."),
("tweak.ai.copilotPolicy.title", "Turn off Windows Copilot (by policy)", "إيقاف Windows Copilot (عبر السياسة)"),
("tweak.ai.copilotPolicy.why", "Sets Microsoft's \"Turn off Windows Copilot\" policy for your account.", "يضبط سياسة Microsoft «إيقاف Windows Copilot» لحسابك."),
("tweak.ai.copilotPolicy.warning", "Microsoft says this policy covers the older built-in Copilot panel. On newer versions Copilot is an app: remove the Copilot app as well.", "تقول Microsoft إن هذه السياسة تخص لوحة Copilot المدمجة القديمة. في الإصدارات الأحدث أصبح Copilot تطبيقاً: أزِل تطبيق Copilot أيضاً."),
("tweak.ai.copilotApp.title", "Remove the Copilot app", "إزالة تطبيق Copilot"),
("tweak.ai.copilotApp.why", "Removes the Copilot app for every user. Copilot in Edge and Office is separate.", "يزيل تطبيق Copilot لكل المستخدمين. أما Copilot في Edge وOffice فمنفصل."),
("tweak.ai.copilotApp.warning", "The Copilot key on new keyboards will do nothing until you reinstall it.", "لن يفعل مفتاح Copilot في لوحات المفاتيح الحديثة شيئاً حتى تعيد تثبيته."),
("tweak.ai.recallOff.title", "Turn off Recall (by policy)", "إيقاف Recall (عبر السياسة)"),
("tweak.ai.recallOff.why", "Recall saves snapshots of your screen to search later, which uses the processor, memory and disk. This turns it off with Microsoft's documented policies; Microsoft says Windows then removes the Recall component after a restart.", "يحفظ Recall لقطات من شاشتك للبحث فيها لاحقاً، وهذا يستهلك المعالج والذاكرة والقرص. يوقفه هذا بسياسات Microsoft الموثّقة؛ وتقول Microsoft إن Windows يزيل مكوّن Recall بعد إعادة التشغيل."),
("tweak.ai.recallOff.warning", "Only matters on Copilot+ PCs that have Recall. Check afterwards that old snapshots are gone in Settings > Privacy & security > Recall & snapshots.", "يهم فقط على أجهزة Copilot+ التي فيها Recall. تحقق بعدها من زوال اللقطات القديمة في الإعدادات > الخصوصية والأمان > Recall واللقطات."),
("tweak.ai.clickToDo.title", "Turn off Click to Do", "إيقاف Click to Do"),
("tweak.ai.clickToDo.why", "Click to Do analyses what is on your screen to suggest AI actions. This turns it off with Microsoft's policy. Only present on Copilot+ PCs.", "يحلل Click to Do ما على شاشتك ليقترح إجراءات ذكاء اصطناعي. يوقفه هذا بسياسة Microsoft. موجود فقط على أجهزة Copilot+."),
("tweak.ai.paint.title", "Turn off AI features in Paint", "إيقاف ميزات الذكاء الاصطناعي في الرسام"),
("tweak.ai.paint.why", "Turns off Cocreator, Image Creator and Generative fill in Paint. Normal drawing and editing stay.", "يوقف Cocreator وImage Creator والتعبئة التوليدية في الرسام. يبقى الرسم والتحرير العادي."),
("tweak.ai.notepad.title", "Turn off AI features in Notepad", "إيقاف ميزات الذكاء الاصطناعي في المفكرة"),
("tweak.ai.notepad.why", "Turns off Copilot writing features in Notepad. Notepad itself stays.", "يوقف ميزات الكتابة بـCopilot في المفكرة. تبقى المفكرة نفسها."),
("tweak.ai.edgeCopilot.title", "Turn off Copilot in Edge", "إيقاف Copilot في Edge"),
("tweak.ai.edgeCopilot.why", "Turns off the Edge sidebar that hosts Copilot and stops Copilot reading the page you are on. Edge itself is not removed or changed otherwise.", "يوقف الشريط الجانبي في Edge الذي يستضيف Copilot ويمنع Copilot من قراءة الصفحة التي تتصفحها. لا يُزال Edge ولا يتغيّر فيه شيء آخر."),
("tweak.ai.edgeCopilot.warning", "The whole Edge sidebar goes, including any sidebar apps you use.", "يختفي الشريط الجانبي في Edge كاملاً، بما فيه أي تطبيقات جانبية تستخدمها."),
("tweak.ai.searchHighlights.title", "Turn off search highlights", "إيقاف أبرز عناصر البحث"),
("tweak.ai.searchHighlights.why", "Stops the search box from downloading and showing daily online content and suggestions.", "يمنع مربع البحث من تنزيل وعرض محتوى واقتراحات يومية من الإنترنت."),
("tweak.ai.m365CopilotApp.title", "Remove the Microsoft 365 Copilot app", "إزالة تطبيق Microsoft 365 Copilot"),
("tweak.ai.m365CopilotApp.why", "Removes the Microsoft 365 Copilot app (formerly the Office app). Word, Excel and the other Office programs are separate and stay.", "يزيل تطبيق Microsoft 365 Copilot (تطبيق Office سابقاً). أما Word وExcel وبقية برامج Office فمنفصلة وتبقى."),
("tweak.ai.m365CopilotApp.warning", "If you open your Office files from this app, keep it.", "إن كنت تفتح ملفات Office من هذا التطبيق فأبقِه."),
# Tell first, then ask: every action that changes or loads the PC.
("journal.undoOne.title", "Undo this change?", "التراجع عن هذا التغيير؟"),
("journal.undoOne.entry", "PC Doctor will put this one setting back to the value it had before. If something else changed it since, nothing is overwritten and you are told.", "سيعيد طبيب الحاسوب هذا الإعداد إلى قيمته السابقة. إن غيّره شيء آخر منذ ذلك الحين فلن يُستبدل شيء وسيتم إخبارك."),
("journal.undoOne.batch", "PC Doctor will put back every setting that was changed together with this one. If something else changed any of them since, those are not overwritten and you are told.", "سيعيد طبيب الحاسوب كل الإعدادات التي تغيّرت مع هذا الإعداد. إن غيّر شيء آخر أياً منها منذ ذلك الحين فلن تُستبدل وسيتم إخبارك."),
("journal.undoOne.button", "Undo", "تراجع"),
("repairs.sfc.ask", "Run System File Checker?", "تشغيل مدقق ملفات النظام؟"),
("repairs.sfc.consent", "Windows' own tool (sfc /scannow) checks protected system files and replaces damaged ones with good copies. It can take 10 to 30 minutes and uses the disk while it runs. You can cancel it.", "أداة Windows نفسها (sfc /scannow) تفحص ملفات النظام المحمية وتستبدل التالف منها بنسخ سليمة. قد تستغرق 10 إلى 30 دقيقة وتستخدم القرص أثناء عملها. يمكنك إلغاؤها."),
("repairs.sfc.button", "Run it", "شغّلها"),
("repairs.verifierReset.consent", "This turns Driver Verifier off for every driver. It takes effect after a restart.", "يوقف هذا Driver Verifier لكل التعريفات. يسري بعد إعادة التشغيل."),
("repairs.verifierReset.button", "Turn it off", "أوقفه"),
("bench.consent.title", "Start the measurement?", "بدء القياس؟"),
("bench.consent.body", "For a few minutes PC Doctor will load the processor and memory on purpose, and the disk too if the disk test is ticked (it writes a temporary test file and deletes it). The PC will feel slow and the fans may speed up. Nothing is changed or installed. It stops by itself, and you can cancel at any time.", "لبضع دقائق سيحمّل طبيب الحاسوب المعالج والذاكرة عمداً، والقرص أيضاً إن كان اختبار القرص محدداً (يكتب ملف اختبار مؤقتاً ثم يحذفه). سيبدو الجهاز بطيئاً وقد تتسارع المراوح. لا يتغيّر شيء ولا يُثبَّت شيء. يتوقف تلقائياً ويمكنك الإلغاء في أي وقت."),
("bench.consent.button", "Start", "ابدأ"),
("bench.latency.consent.title", "Trace driver delays?", "تتبّع تأخيرات التعريفات؟"),
("bench.latency.consent.body", "Windows will record driver activity for a short time, with administrator rights, to find which driver causes stutter. The recording stays on this PC and is deleted after it is read. Nothing is changed.", "سيسجّل Windows نشاط التعريفات لوقت قصير، بصلاحيات المسؤول، لمعرفة أي تعريف يسبب التقطّع. يبقى التسجيل على هذا الجهاز ويُحذف بعد قراءته. لا يتغيّر شيء."),
("history.schedule.consent.title", "Change the scheduled check?", "تغيير الفحص المجدول؟"),
("history.schedule.consent.on", "PC Doctor will add one task to Windows Task Scheduler, in the folder \"PC Doctor\". It runs a read-only Health Check at that time, only looks, changes nothing, and tells you quietly if something new turns up. You can turn it off here at any time.", "سيضيف طبيب الحاسوب مهمة واحدة إلى «مجدول المهام» في Windows، في المجلد «PC Doctor». تُجري فحصاً صحياً للقراءة فقط في ذلك الوقت، تنظر فقط ولا تغيّر شيئاً، وتخبرك بهدوء إن ظهر جديد. يمكنك إيقافها من هنا في أي وقت."),
("history.schedule.consent.off", "PC Doctor will remove its task from Windows Task Scheduler. No more automatic checks will run.", "سيزيل طبيب الحاسوب مهمته من «مجدول المهام» في Windows. لن تُجرى فحوص تلقائية بعد الآن."),
("history.schedule.consent.button", "OK, do it", "موافق، نفّذ"),
("status.copyFailed", "Could not copy: another program is using the clipboard. Try again.", "تعذّر النسخ: برنامج آخر يستخدم الحافظة. حاول مجدداً."),
("status.exportFailed", "Could not save the file: {0}", "تعذّر حفظ الملف: {0}"),
("app.error.title", "Something went wrong", "حدث خطأ ما"),
("app.error.body", "PC Doctor hit an unexpected error and stopped that one action. Nothing else was affected and the app is still running.\n\n{0}\n\nDetails were saved on this PC only, in:\n{1}", "واجه طبيب الحاسوب خطأً غير متوقع وأوقف ذلك الإجراء فقط. لم يتأثر شيء آخر والتطبيق ما زال يعمل.\n\n{0}\n\nحُفظت التفاصيل على هذا الجهاز فقط، في:\n{1}"),
]
S += _app("tips", "Tips", "«تلميحات»")
S += _app("feedbackHub", "Feedback Hub", "«مركز الملاحظات»")
S += _app("cortana", "Cortana", "Cortana")
S += _app("maps", "Maps", "«الخرائط»")
S += _app("people", "People", "«الأشخاص»")
S += _app("skype", "Skype", "Skype")
S += _app("3dViewer", "3D Viewer", "«عارض ثلاثي الأبعاد»")
S += _app("mixedReality", "Mixed Reality Portal", "«مدخل الواقع المختلط»")
S += _app("linkedIn", "LinkedIn", "LinkedIn")
S += _app("devHome", "Dev Home", "Dev Home")
S += _app("powerAutomate", "Power Automate", "Power Automate")
S += _app("moviesTv", "Movies & TV", "«الأفلام والتلفزيون»")
S += _app("todo", "Microsoft To Do", "Microsoft To Do")
S += _app("family", "Microsoft Family", "Microsoft Family")
S += _app("bingSearch", "the Bing web search add-on", "إضافة بحث الويب Bing")
S += _app("xbox", "the Xbox app", "تطبيق Xbox", ("Keep it if you play PC Game Pass or Xbox games: they need it.", "أبقِه إن كنت تلعب ألعاب PC Game Pass أو Xbox: فهي تحتاجه."))
S += _app("phoneLink", "Phone Link", "«ربط الهاتف»", ("Keep it if you read phone messages or notifications on this PC.", "أبقِه إن كنت تقرأ رسائل هاتفك أو إشعاراته على هذا الجهاز."))
S += _app("outlookNew", "the new Outlook", "Outlook الجديد", ("Keep it if this is where you read your email. Accounts set up in it will need setting up again after a reinstall.", "أبقِه إن كان هذا مكان قراءة بريدك. الحسابات المعدّة فيه تحتاج إعداداً جديداً بعد إعادة التثبيت."))
S += _app("teams", "Microsoft Teams", "Microsoft Teams", ("Keep it if you use Teams for work, school or calls.", "أبقِه إن كنت تستخدم Teams للعمل أو الدراسة أو المكالمات."))
S += _app("quickAssist", "Quick Assist", "«المساعدة السريعة»", ("Keep it if someone helps you with this PC remotely through Quick Assist.", "أبقِه إن كان أحد يساعدك في هذا الجهاز عن بُعد عبر «المساعدة السريعة»."))
