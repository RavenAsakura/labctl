#include "MainWindow.hpp"
#include "LabctlRunner.hpp"
#include "MetricHistoryWidget.hpp"

#include <QButtonGroup>
#include <QCheckBox>
#include <QDateTime>
#include <QFrame>
#include <QHBoxLayout>
#include <QLabel>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QList>
#include <QMessageBox>
#include <QPair>
#include <QPlainTextEdit>
#include <QProcess>
#include <QPushButton>
#include <QRegularExpression>
#include <QScrollArea>
#include <QStackedWidget>
#include <QStringList>
#include <QTimer>
#include <QTreeWidget>
#include <QVBoxLayout>
#include <QWidget>
#include <algorithm>

namespace
{

QFrame* createMetricCard(
    const QString& title,
    const QString& subtitle,
    QLabel*& valueLabel)
{
    auto* card = new QFrame;
    card->setObjectName(QStringLiteral("metricCard"));
    card->setMinimumHeight(118);

    auto* layout = new QVBoxLayout(card);
    layout->setContentsMargins(20, 18, 20, 18);
    layout->setSpacing(6);

    auto* titleLabel = new QLabel(title);
    titleLabel->setObjectName(QStringLiteral("metricTitle"));

    valueLabel = new QLabel(QStringLiteral("--"));
    valueLabel->setObjectName(QStringLiteral("metricValue"));

    auto* subtitleLabel = new QLabel(subtitle);
    subtitleLabel->setObjectName(QStringLiteral("metricSubtitle"));

    layout->addWidget(titleLabel);
    layout->addStretch();
    layout->addWidget(valueLabel);
    layout->addWidget(subtitleLabel);

    return card;
}

QWidget* createServiceRow(
    const QString& serviceName,
    QLabel*& statusLabel)
{
    auto* row = new QWidget;
    auto* layout = new QHBoxLayout(row);

    layout->setContentsMargins(0, 8, 0, 8);

    auto* nameLabel = new QLabel(serviceName);
    nameLabel->setObjectName(QStringLiteral("serviceName"));

    statusLabel = new QLabel(QStringLiteral("Unknown"));
    statusLabel->setObjectName(QStringLiteral("serviceStatus"));

    layout->addWidget(nameLabel);
    layout->addStretch();
    layout->addWidget(statusLabel);

    return row;
}

QWidget* createInfoRow(
    const QString& name,
    QLabel*& valueLabel)
{
    auto* row = new QWidget;
    auto* layout = new QHBoxLayout(row);
    layout->setContentsMargins(0, 6, 0, 6);

    auto* nameLabel = new QLabel(name);
    nameLabel->setObjectName(QStringLiteral("serviceName"));

    valueLabel = new QLabel(QStringLiteral("--"));
    valueLabel->setObjectName(QStringLiteral("infoValue"));
    valueLabel->setAlignment(Qt::AlignRight | Qt::AlignVCenter);
    valueLabel->setWordWrap(true);
    valueLabel->setMaximumWidth(210);

    layout->addWidget(nameLabel);
    layout->addStretch();
    layout->addWidget(valueLabel);

    return row;
}

} // namespace

MainWindow::MainWindow(QWidget* parent)
    : QMainWindow(parent),
      labctlRunner_(new LabctlRunner(this))
{
    buildInterface();
    configureRunner();

    setWindowTitle(QStringLiteral("LabCTL"));
    resize(1280, 820);

    commandOutput_->appendPlainText(
        QStringLiteral("LabCTL GUI initialized.")
    );

    if (labctlRunner_->executablePath().isEmpty()) {
        healthBadgeLabel_->setText(
            QStringLiteral("CLI Not Found")
        );

        commandOutput_->appendPlainText(
            QStringLiteral(
                "[WARNING] LabCTL CLI executable was not found."
            )
        );
    } else {
        healthBadgeLabel_->setText(
            QStringLiteral("CLI Ready")
        );

        commandOutput_->appendPlainText(
            QStringLiteral("[OK] CLI: %1")
                .arg(labctlRunner_->executablePath())
        );
    }
}

MainWindow::~MainWindow()
{
    if (labctlRunner_ != nullptr) {
        disconnect(labctlRunner_, nullptr, this, nullptr);
        labctlRunner_->stop();
    }
}

void MainWindow::buildInterface()
{
    auto* central = new QWidget(this);
    setCentralWidget(central);

    auto* rootLayout = new QHBoxLayout(central);
    rootLayout->setContentsMargins(0, 0, 0, 0);
    rootLayout->setSpacing(0);

    /*
     * Sidebar
     */

    auto* sidebar = new QFrame;
    sidebar->setObjectName(QStringLiteral("sidebar"));
    sidebar->setFixedWidth(220);

    auto* sidebarLayout = new QVBoxLayout(sidebar);
    sidebarLayout->setContentsMargins(18, 24, 18, 24);
    sidebarLayout->setSpacing(8);

    auto* appTitle = new QLabel(QStringLiteral("LabCTL"));
    appTitle->setObjectName(QStringLiteral("appTitle"));

    auto* appSubtitle = new QLabel(
        QStringLiteral("Linux Lab Control")
    );
    appSubtitle->setObjectName(QStringLiteral("appSubtitle"));

    sidebarLayout->addWidget(appTitle);
    sidebarLayout->addWidget(appSubtitle);
    sidebarLayout->addSpacing(28);

    auto* navigationGroup = new QButtonGroup(this);
    navigationGroup->setExclusive(true);

    const QStringList pages = {
        QStringLiteral("Dashboard"),
        QStringLiteral("Monitor"),
        QStringLiteral("Services"),
        QStringLiteral("Workloads"),
        QStringLiteral("Network"),
        QStringLiteral("Storage"),
        QStringLiteral("Reports"),
        QStringLiteral("Settings")
    };

    for (const QString& page : pages) {
        auto* button = new QPushButton(page);

        button->setObjectName(
            QStringLiteral("navigationButton")
        );
        button->setProperty("page", page);

        button->setCheckable(true);
        button->setMinimumHeight(42);

        if (page == QStringLiteral("Dashboard")) {
            button->setChecked(true);
        }

        navigationGroup->addButton(button);
        sidebarLayout->addWidget(button);

        connect(
            button,
            &QPushButton::clicked,
            this,
            [this, page]()
            {
                showPage(page);
            }
        );
    }

    sidebarLayout->addStretch();

    auto* versionLabel = new QLabel(
        QStringLiteral("LabCTL GUI 0.3.0")
    );
    versionLabel->setObjectName(
        QStringLiteral("versionLabel")
    );

    sidebarLayout->addWidget(versionLabel);

    /*
     * Main content
     */

    auto* content = new QWidget;
    content->setObjectName(QStringLiteral("contentArea"));

    auto* contentLayout = new QVBoxLayout(content);
    contentLayout->setContentsMargins(28, 24, 28, 24);
    contentLayout->setSpacing(20);

    /*
     * Header
     */

    auto* headerLayout = new QHBoxLayout;
    auto* headerTextLayout = new QVBoxLayout;

    pageTitleLabel_ = new QLabel(
        QStringLiteral("Dashboard")
    );
    pageTitleLabel_->setObjectName(
        QStringLiteral("pageTitle")
    );

    pageSubtitleLabel_ = new QLabel(
        QStringLiteral(
            "System overview and laboratory services"
        )
    );
    pageSubtitleLabel_->setObjectName(
        QStringLiteral("pageSubtitle")
    );

    headerTextLayout->addWidget(pageTitleLabel_);
    headerTextLayout->addWidget(pageSubtitleLabel_);

    healthBadgeLabel_ = new QLabel(
        QStringLiteral("Starting")
    );
    healthBadgeLabel_->setObjectName(
        QStringLiteral("healthBadge")
    );

    refreshButton_ = new QPushButton(
        QStringLiteral("Refresh")
    );
    refreshButton_->setObjectName(
        QStringLiteral("primaryButton")
    );
    refreshButton_->setMinimumHeight(38);

    cancelButton_ = new QPushButton(QStringLiteral("Cancel"));
    cancelButton_->setObjectName(QStringLiteral("secondaryButton"));
    cancelButton_->setMinimumHeight(38);
    cancelButton_->setEnabled(false);

    headerLayout->addLayout(headerTextLayout);
    headerLayout->addStretch();
    headerLayout->addWidget(healthBadgeLabel_);
    headerLayout->addWidget(cancelButton_);
    headerLayout->addWidget(refreshButton_);

    contentLayout->addLayout(headerLayout);

    pageStack_ = new QStackedWidget;
    pageStack_->setObjectName(QStringLiteral("pageStack"));

    auto* dashboardPage = new QWidget;
    auto* dashboardPageLayout = new QVBoxLayout(dashboardPage);
    dashboardPageLayout->setContentsMargins(0, 0, 0, 0);
    auto* dashboardScroll = new QScrollArea;
    dashboardScroll->setObjectName(QStringLiteral("dashboardScroll"));
    dashboardScroll->setWidgetResizable(true);
    dashboardScroll->setFrameShape(QFrame::NoFrame);
    auto* dashboardContent = new QWidget;
    auto* dashboardLayout = new QVBoxLayout(dashboardContent);
    dashboardLayout->setContentsMargins(0, 0, 0, 0);
    dashboardLayout->setSpacing(20);
    dashboardScroll->setWidget(dashboardContent);
    dashboardPageLayout->addWidget(dashboardScroll);

    auto* profilePanel = new QFrame;
    profilePanel->setObjectName(QStringLiteral("panel"));
    auto* profileLayout = new QHBoxLayout(profilePanel);
    profileLayout->setContentsMargins(18, 12, 18, 12);

    auto* profileTitle = new QLabel(QStringLiteral("Profile"));
    profileTitle->setObjectName(QStringLiteral("serviceName"));
    profileValueLabel_ = new QLabel(QStringLiteral("--"));
    profileValueLabel_->setObjectName(QStringLiteral("statusValue"));

    auto* powerTitle = new QLabel(QStringLiteral("Power"));
    powerTitle->setObjectName(QStringLiteral("serviceName"));
    powerValueLabel_ = new QLabel(QStringLiteral("--"));
    powerValueLabel_->setObjectName(QStringLiteral("statusValue"));

    auto* workButton = new QPushButton(QStringLiteral("Work"));
    auto* travelButton = new QPushButton(QStringLiteral("Travel"));
    workButton->setObjectName(QStringLiteral("profileButton"));
    travelButton->setObjectName(QStringLiteral("profileButton"));

    connect(workButton, &QPushButton::clicked, this, [this]() {
        runProfileAction(QStringLiteral("work"));
    });
    connect(travelButton, &QPushButton::clicked, this, [this]() {
        runProfileAction(QStringLiteral("travel"));
    });

    profileLayout->addWidget(profileTitle);
    profileLayout->addWidget(profileValueLabel_);
    profileLayout->addSpacing(24);
    profileLayout->addWidget(powerTitle);
    profileLayout->addWidget(powerValueLabel_);
    profileLayout->addStretch();
    profileLayout->addWidget(workButton);
    profileLayout->addWidget(travelButton);
    dashboardLayout->addWidget(profilePanel);

    /*
     * Dashboard metric cards
     */

    auto* metricLayout = new QHBoxLayout;
    metricLayout->setSpacing(16);

    metricLayout->addWidget(
        createMetricCard(
            QStringLiteral("CPU"),
            QStringLiteral("Usage and temperature"),
            cpuValueLabel_
        )
    );

    metricLayout->addWidget(
        createMetricCard(
            QStringLiteral("Memory"),
            QStringLiteral("Usage and allocated RAM"),
            memoryValueLabel_
        )
    );

    metricLayout->addWidget(
        createMetricCard(
            QStringLiteral("GPU"),
            QStringLiteral("Usage and temperature"),
            gpuValueLabel_
        )
    );

    metricLayout->addWidget(
        createMetricCard(
            QStringLiteral("Storage"),
            QStringLiteral("Root filesystem usage"),
            storageValueLabel_
        )
    );

    cpuValueLabel_->setProperty("dashboardMetric", "cpu");
    memoryValueLabel_->setProperty("dashboardMetric", "memory");
    gpuValueLabel_->setProperty("dashboardMetric", "gpu");
    storageValueLabel_->setProperty("dashboardMetric", "storage");

    dashboardLayout->addLayout(metricLayout);

    auto* historyPanel = new QFrame;
    historyPanel->setObjectName(QStringLiteral("panel"));
    auto* historyLayout = new QHBoxLayout(historyPanel);
    historyLayout->setContentsMargins(12, 10, 12, 10);
    historyLayout->setSpacing(12);

    cpuHistory_ = new MetricHistoryWidget(QStringLiteral("CPU"), QStringLiteral("%"));
    memoryHistory_ = new MetricHistoryWidget(QStringLiteral("Memory"), QStringLiteral("%"));
    temperatureHistory_ = new MetricHistoryWidget(QStringLiteral("CPU Temp"), QStringLiteral("°C"));
    networkHistory_ = new MetricHistoryWidget(QStringLiteral("Network"), QStringLiteral("KiB/s"));
    cpuHistory_->setProperty("historyMetric", "cpu");
    memoryHistory_->setProperty("historyMetric", "memory");
    temperatureHistory_->setProperty("historyMetric", "temperature");
    networkHistory_->setProperty("historyMetric", "network");
    historyLayout->addWidget(cpuHistory_, 1);
    historyLayout->addWidget(memoryHistory_, 1);
    historyLayout->addWidget(temperatureHistory_, 1);
    historyLayout->addWidget(networkHistory_, 1);
    dashboardLayout->addWidget(historyPanel);

    /*
     * Lower panels
     */

    auto* lowerLayout = new QHBoxLayout;
    lowerLayout->setSpacing(16);

    auto* servicesPanel = new QFrame;
    servicesPanel->setObjectName(QStringLiteral("panel"));
    servicesPanel->setMinimumWidth(360);

    auto* servicesLayout = new QVBoxLayout(
        servicesPanel
    );
    servicesLayout->setContentsMargins(
        20,
        18,
        20,
        18
    );

    auto* servicesTitle = new QLabel(
        QStringLiteral("Laboratory Services")
    );
    servicesTitle->setObjectName(
        QStringLiteral("panelTitle")
    );

    servicesLayout->addWidget(servicesTitle);
    servicesLayout->addSpacing(10);

    servicesLayout->addWidget(
        createServiceRow(
            QStringLiteral("Docker"),
            dockerStatusLabel_
        )
    );

    servicesLayout->addWidget(
        createServiceRow(
            QStringLiteral("VMware"),
            vmwareStatusLabel_
        )
    );

    servicesLayout->addWidget(
        createServiceRow(
            QStringLiteral("Libvirt"),
            libvirtStatusLabel_
        )
    );

    servicesLayout->addWidget(
        createServiceRow(
            QStringLiteral("OneDrive"),
            oneDriveStatusLabel_
        )
    );

    servicesLayout->addWidget(
        createServiceRow(
            QStringLiteral("Ollama"),
            ollamaStatusLabel_
        )
    );

    servicesLayout->addStretch();

    auto* connectivityPanel = new QFrame;
    connectivityPanel->setObjectName(QStringLiteral("panel"));
    auto* connectivityLayout = new QVBoxLayout(connectivityPanel);
    connectivityLayout->setContentsMargins(20, 18, 20, 18);

    auto* connectivityTitle = new QLabel(QStringLiteral("Connectivity"));
    connectivityTitle->setObjectName(QStringLiteral("panelTitle"));
    connectivityLayout->addWidget(connectivityTitle);
    connectivityLayout->addWidget(
        createInfoRow(QStringLiteral("Network"), networkValueLabel_)
    );
    connectivityLayout->addWidget(
        createInfoRow(QStringLiteral("IPv4"), ipValueLabel_)
    );
    connectivityLayout->addWidget(
        createInfoRow(QStringLiteral("VPN"), vpnValueLabel_)
    );
    connectivityLayout->addWidget(
        createInfoRow(QStringLiteral("Battery"), batteryValueLabel_)
    );
    connectivityLayout->addStretch();

    auto* workloadPanel = new QFrame;
    workloadPanel->setObjectName(QStringLiteral("panel"));
    auto* workloadLayout = new QVBoxLayout(workloadPanel);
    workloadLayout->setContentsMargins(20, 18, 20, 18);

    auto* workloadTitle = new QLabel(QStringLiteral("Lab Activity"));
    workloadTitle->setObjectName(QStringLiteral("panelTitle"));
    workloadLayout->addWidget(workloadTitle);
    workloadLayout->addWidget(
        createInfoRow(QStringLiteral("Containers"), containersValueLabel_)
    );
    workloadLayout->addWidget(
        createInfoRow(QStringLiteral("Libvirt VMs"), libvirtVmValueLabel_)
    );
    workloadLayout->addWidget(
        createInfoRow(QStringLiteral("VMware VMs"), vmwareVmValueLabel_)
    );
    workloadLayout->addWidget(
        createInfoRow(QStringLiteral("VirtualBox VMs"), virtualboxVmValueLabel_)
    );
    workloadLayout->addStretch();

    lowerLayout->addWidget(servicesPanel, 1);
    lowerLayout->addWidget(connectivityPanel, 1);
    lowerLayout->addWidget(workloadPanel, 1);

    dashboardLayout->addLayout(lowerLayout, 1);

    auto* alertsPanel = new QFrame;
    alertsPanel->setObjectName(QStringLiteral("alertsPanel"));
    auto* alertsLayout = new QHBoxLayout(alertsPanel);
    alertsLayout->setContentsMargins(16, 10, 16, 10);

    auto* alertsTitle = new QLabel(QStringLiteral("Attention"));
    alertsTitle->setObjectName(QStringLiteral("panelTitle"));
    alertsLabel_ = new QLabel(QStringLiteral("No current alerts."));
    alertsLabel_->setObjectName(QStringLiteral("alertsText"));
    alertsLabel_->setWordWrap(true);

    alertsLayout->addWidget(alertsTitle);
    alertsLayout->addSpacing(12);
    alertsLayout->addWidget(alertsLabel_, 1);
    dashboardLayout->addWidget(alertsPanel);

    auto* dashboardFooter = new QHBoxLayout;
    lastUpdatedLabel_ = new QLabel(QStringLiteral("Not updated yet"));
    lastUpdatedLabel_->setObjectName(QStringLiteral("versionLabel"));
    autoRefreshCheck_ = new QCheckBox(QStringLiteral("Auto-refresh 10s"));
    autoRefreshCheck_->setObjectName(QStringLiteral("autoRefreshCheck"));
    detailsButton_ = new QPushButton(QStringLiteral("Technical Details"));
    detailsButton_->setObjectName(QStringLiteral("secondaryButton"));
    detailsButton_->setCheckable(true);

    dashboardFooter->addWidget(lastUpdatedLabel_);
    dashboardFooter->addStretch();
    dashboardFooter->addWidget(autoRefreshCheck_);
    dashboardFooter->addWidget(detailsButton_);
    dashboardLayout->addLayout(dashboardFooter);

    dashboardOutputPanel_ = new QFrame;
    dashboardOutputPanel_->setObjectName(QStringLiteral("panel"));
    auto* outputLayout = new QVBoxLayout(dashboardOutputPanel_);
    outputLayout->setContentsMargins(20, 18, 20, 18);

    auto* outputTitle = new QLabel(QStringLiteral("Technical Output"));
    outputTitle->setObjectName(QStringLiteral("panelTitle"));
    commandOutput_ = new QPlainTextEdit;
    commandOutput_->setObjectName(QStringLiteral("commandOutput"));
    commandOutput_->setReadOnly(true);
    commandOutput_->setMinimumHeight(150);

    outputLayout->addWidget(outputTitle);
    outputLayout->addWidget(commandOutput_);
    dashboardOutputPanel_->setVisible(false);
    dashboardLayout->addWidget(dashboardOutputPanel_);

    connect(
        detailsButton_,
        &QPushButton::toggled,
        dashboardOutputPanel_,
        &QWidget::setVisible
    );

    dashboardRefreshTimer_ = new QTimer(this);
    dashboardRefreshTimer_->setInterval(10000);
    connect(
        dashboardRefreshTimer_,
        &QTimer::timeout,
        this,
        [this]()
        {
            if ((currentPage_ == QStringLiteral("Dashboard") ||
                 currentPage_ == QStringLiteral("Workloads")) &&
                !labctlRunner_->isRunning()) {
                refreshDashboard();
            }
        }
    );
    connect(
        autoRefreshCheck_,
        &QCheckBox::toggled,
        this,
        [this](bool enabled)
        {
            if (enabled) {
                dashboardRefreshTimer_->start();
            } else {
                dashboardRefreshTimer_->stop();
            }
        }
    );

    pageIndexes_.insert(
        QStringLiteral("Dashboard"),
        pageStack_->addWidget(dashboardPage)
    );
    pageOutputs_.insert(QStringLiteral("Dashboard"), commandOutput_);

    QPlainTextEdit* monitorOutput = nullptr;
    QPlainTextEdit* servicesOutput = nullptr;
    QPlainTextEdit* workloadsOutput = nullptr;
    QPlainTextEdit* networkOutput = nullptr;
    QPlainTextEdit* storageOutput = nullptr;
    QPlainTextEdit* reportsOutput = nullptr;
    QPlainTextEdit* settingsOutput = nullptr;

    pageIndexes_.insert(
        QStringLiteral("Monitor"),
        pageStack_->addWidget(createCommandPage(
            QStringLiteral(
                "Detailed CPU, memory, GPU, power, and process information."
            ),
            monitorOutput
        ))
    );
    pageIndexes_.insert(
        QStringLiteral("Services"),
        pageStack_->addWidget(createServicesPage(servicesOutput))
    );
    pageIndexes_.insert(
        QStringLiteral("Workloads"),
        pageStack_->addWidget(createWorkloadsPage(workloadsOutput))
    );
    pageIndexes_.insert(
        QStringLiteral("Network"),
        pageStack_->addWidget(createCommandPage(
            QStringLiteral("Network interfaces and current traffic rates."),
            networkOutput
        ))
    );
    pageIndexes_.insert(
        QStringLiteral("Storage"),
        pageStack_->addWidget(createCommandPage(
            QStringLiteral("Filesystem usage and disk throughput."),
            storageOutput
        ))
    );
    pageIndexes_.insert(
        QStringLiteral("Reports"),
        pageStack_->addWidget(createCommandPage(
            QStringLiteral("Read-only workstation health diagnostic."),
            reportsOutput
        ))
    );
    pageIndexes_.insert(
        QStringLiteral("Settings"),
        pageStack_->addWidget(createCommandPage(
            QStringLiteral("Detected LabCTL, operating system, and hardware information."),
            settingsOutput
        ))
    );

    pageOutputs_.insert(QStringLiteral("Monitor"), monitorOutput);
    pageOutputs_.insert(QStringLiteral("Services"), servicesOutput);
    pageOutputs_.insert(QStringLiteral("Workloads"), workloadsOutput);
    pageOutputs_.insert(QStringLiteral("Network"), networkOutput);
    pageOutputs_.insert(QStringLiteral("Storage"), storageOutput);
    pageOutputs_.insert(QStringLiteral("Reports"), reportsOutput);
    pageOutputs_.insert(QStringLiteral("Settings"), settingsOutput);

    contentLayout->addWidget(pageStack_, 1);

    rootLayout->addWidget(sidebar);
    rootLayout->addWidget(content, 1);
}

QWidget* MainWindow::createCommandPage(
    const QString& description,
    QPlainTextEdit*& output)
{
    auto* page = new QWidget;
    auto* layout = new QVBoxLayout(page);
    layout->setContentsMargins(0, 0, 0, 0);
    layout->setSpacing(16);

    auto* descriptionLabel = new QLabel(description);
    descriptionLabel->setObjectName(QStringLiteral("pageDescription"));
    descriptionLabel->setWordWrap(true);

    auto* outputPanel = new QFrame;
    outputPanel->setObjectName(QStringLiteral("panel"));
    auto* outputLayout = new QVBoxLayout(outputPanel);
    outputLayout->setContentsMargins(20, 18, 20, 18);

    auto* outputTitle = new QLabel(QStringLiteral("Command Output"));
    outputTitle->setObjectName(QStringLiteral("panelTitle"));

    output = new QPlainTextEdit;
    output->setObjectName(QStringLiteral("commandOutput"));
    output->setReadOnly(true);
    output->setPlaceholderText(
        QStringLiteral("Select this page or press Refresh to load data.")
    );

    outputLayout->addWidget(outputTitle);
    outputLayout->addWidget(output, 1);
    layout->addWidget(descriptionLabel);
    layout->addWidget(outputPanel, 1);

    return page;
}

QWidget* MainWindow::createServicesPage(QPlainTextEdit*& output)
{
    auto* page = new QWidget;
    auto* layout = new QVBoxLayout(page);
    layout->setContentsMargins(0, 0, 0, 0);
    layout->setSpacing(16);

    auto* description = new QLabel(
        QStringLiteral(
            "Control laboratory services. Privileged actions use the "
            "desktop PolicyKit authorization dialog."
        )
    );
    description->setObjectName(QStringLiteral("pageDescription"));
    description->setWordWrap(true);
    layout->addWidget(description);

    auto* controlsPanel = new QFrame;
    controlsPanel->setObjectName(QStringLiteral("panel"));
    auto* controlsLayout = new QVBoxLayout(controlsPanel);
    controlsLayout->setContentsMargins(20, 18, 20, 18);
    controlsLayout->setSpacing(8);

    auto* controlsTitle = new QLabel(QStringLiteral("Service Controls"));
    controlsTitle->setObjectName(QStringLiteral("panelTitle"));
    controlsLayout->addWidget(controlsTitle);

    const QList<QPair<QString, QString>> services = {
        {QStringLiteral("Docker"), QStringLiteral("docker")},
        {QStringLiteral("QEMU / Libvirt"), QStringLiteral("libvirt")},
        {QStringLiteral("VMware"), QStringLiteral("vmware")},
        {QStringLiteral("VirtualBox"), QStringLiteral("virtualbox")},
        {QStringLiteral("Ollama"), QStringLiteral("ollama")}
    };

    for (const auto& service : services) {
        auto* row = new QWidget;
        auto* rowLayout = new QHBoxLayout(row);
        rowLayout->setContentsMargins(0, 4, 0, 4);

        auto* name = new QLabel(service.first);
        name->setObjectName(QStringLiteral("serviceName"));
        rowLayout->addWidget(name);
        rowLayout->addStretch();

        const QStringList actions = {
            QStringLiteral("status"),
            QStringLiteral("start"),
            QStringLiteral("stop"),
            QStringLiteral("restart")
        };

        for (const QString& action : actions) {
            auto* button = new QPushButton(
                action.left(1).toUpper() + action.mid(1)
            );
            button->setObjectName(
                QStringLiteral("actionButton")
            );
            button->setProperty("module", service.second);
            button->setProperty("action", action);

            connect(
                button,
                &QPushButton::clicked,
                this,
                [this, service, action]()
                {
                    runServiceAction(
                        service.second,
                        action,
                        service.first
                    );
                }
            );

            rowLayout->addWidget(button);
        }

        controlsLayout->addWidget(row);
    }

    auto* outputPanel = new QFrame;
    outputPanel->setObjectName(QStringLiteral("panel"));
    auto* outputLayout = new QVBoxLayout(outputPanel);
    outputLayout->setContentsMargins(20, 18, 20, 18);

    auto* outputTitle = new QLabel(QStringLiteral("Service Output"));
    outputTitle->setObjectName(QStringLiteral("panelTitle"));

    output = new QPlainTextEdit;
    output->setObjectName(QStringLiteral("commandOutput"));
    output->setReadOnly(true);

    outputLayout->addWidget(outputTitle);
    outputLayout->addWidget(output, 1);
    layout->addWidget(controlsPanel);
    layout->addWidget(outputPanel, 1);

    return page;
}

QWidget* MainWindow::createWorkloadsPage(QPlainTextEdit*& output)
{
    auto* page = new QWidget;
    auto* layout = new QVBoxLayout(page);
    layout->setContentsMargins(0, 0, 0, 0);
    layout->setSpacing(16);

    auto* description = new QLabel(
        QStringLiteral(
            "Read-only inventory of Docker containers and virtual machines. "
            "Use the Services page to control their runtime backends."
        )
    );
    description->setObjectName(QStringLiteral("pageDescription"));
    description->setWordWrap(true);

    auto* inventoryPanel = new QFrame;
    inventoryPanel->setObjectName(QStringLiteral("panel"));
    auto* inventoryLayout = new QVBoxLayout(inventoryPanel);
    inventoryLayout->setContentsMargins(20, 18, 20, 18);

    auto* inventoryTitle = new QLabel(QStringLiteral("Workload Inventory"));
    inventoryTitle->setObjectName(QStringLiteral("panelTitle"));
    workloadsTree_ = new QTreeWidget;
    workloadsTree_->setObjectName(QStringLiteral("workloadsTree"));
    workloadsTree_->setHeaderLabels({
        QStringLiteral("Backend"),
        QStringLiteral("Name"),
        QStringLiteral("State")
    });
    workloadsTree_->setRootIsDecorated(false);
    workloadsTree_->setAlternatingRowColors(true);
    workloadsTree_->setSortingEnabled(true);

    inventoryLayout->addWidget(inventoryTitle);
    inventoryLayout->addWidget(workloadsTree_, 1);

    output = new QPlainTextEdit;
    output->setObjectName(QStringLiteral("commandOutput"));
    output->setReadOnly(true);
    output->setMaximumHeight(140);

    layout->addWidget(description);
    layout->addWidget(inventoryPanel, 1);
    layout->addWidget(output);
    return page;
}

void MainWindow::setControlsBusy(bool busy)
{
    refreshButton_->setEnabled(!busy);
    cancelButton_->setEnabled(busy);

    const QList<QPushButton*> navigationButtons =
        findChildren<QPushButton*>(QStringLiteral("navigationButton"));
    const QList<QPushButton*> actionButtons =
        findChildren<QPushButton*>(QStringLiteral("actionButton"));
    const QList<QPushButton*> profileButtons =
        findChildren<QPushButton*>(QStringLiteral("profileButton"));

    for (QPushButton* button : navigationButtons) {
        button->setEnabled(!busy);
    }

    for (QPushButton* button : actionButtons) {
        button->setEnabled(!busy);
    }

    for (QPushButton* button : profileButtons) {
        button->setEnabled(!busy);
    }
}

void MainWindow::configureRunner()
{
    connect(
        refreshButton_,
        &QPushButton::clicked,
        this,
        &MainWindow::refreshCurrentPage
    );

    connect(
        cancelButton_,
        &QPushButton::clicked,
        this,
        [this]()
        {
            if (!labctlRunner_->isRunning()) {
                return;
            }

            cancellationRequested_ = true;
            cancelButton_->setEnabled(false);
            healthBadgeLabel_->setText(QStringLiteral("Cancelling"));
            labctlRunner_->stop();
        }
    );

    connect(
        labctlRunner_,
        &LabctlRunner::commandStarted,
        this,
        [this](const QString& command)
        {
            outputBuffer_.clear();
            cancellationRequested_ = false;

            setControlsBusy(true);
            refreshButton_->setText(
                QStringLiteral("Running...")
            );

            commandOutput_->appendPlainText(
                QStringLiteral("\n$ %1").arg(command)
            );
        }
    );

    connect(
        labctlRunner_,
        &LabctlRunner::standardOutputReceived,
        this,
        [this](const QString& output)
        {
            outputBuffer_.append(output);

            if (!output.trimmed().isEmpty()) {
                commandOutput_->appendPlainText(
                    output.trimmed()
                );
            }
        }
    );

    connect(
        labctlRunner_,
        &LabctlRunner::standardErrorReceived,
        this,
        [this](const QString& error)
        {
            outputBuffer_.append(error);

            if (!error.trimmed().isEmpty()) {
                commandOutput_->appendPlainText(
                    QStringLiteral("[STDERR] %1")
                        .arg(error.trimmed())
                );
            }
        }
    );

    connect(
        labctlRunner_,
        &LabctlRunner::runnerError,
        this,
        [this](const QString& error)
        {
            activeCommand_ = ActiveCommand::None;

            setControlsBusy(false);
            refreshButton_->setText(
                QStringLiteral("Refresh")
            );

            healthBadgeLabel_->setText(
                QStringLiteral("Command Failed")
            );

            commandOutput_->appendPlainText(
                QStringLiteral("[ERROR] %1").arg(error)
            );
        }
    );

    connect(
        labctlRunner_,
        &LabctlRunner::commandFinished,
        this,
        [this](
            int exitCode,
            QProcess::ExitStatus exitStatus
        )
        {
            const bool success =
                exitStatus == QProcess::NormalExit &&
                exitCode == 0;

            cancelButton_->setEnabled(false);

            if (cancellationRequested_) {
                cancellationRequested_ = false;
                activeCommand_ = ActiveCommand::None;
                setControlsBusy(false);
                refreshButton_->setText(QStringLiteral("Refresh"));
                healthBadgeLabel_->setText(QStringLiteral("Cancelled"));
                commandOutput_->appendPlainText(
                    QStringLiteral("[CANCELLED] Command stopped by the user.")
                );
                return;
            }

            if (!success) {
                activeCommand_ = ActiveCommand::None;

                setControlsBusy(false);
                refreshButton_->setText(
                    QStringLiteral("Refresh")
                );

                healthBadgeLabel_->setText(
                    QStringLiteral("Command Failed")
                );

                commandOutput_->appendPlainText(
                    QStringLiteral(
                        "[FINISHED] Exit code: %1"
                    ).arg(exitCode)
                );

                return;
            }

            if (
                activeCommand_ ==
                ActiveCommand::Dashboard
            ) {
                parseDashboardOutput(outputBuffer_);

                QTimer::singleShot(
                    50,
                    this,
                    &MainWindow::runOneDriveStatus
                );

                return;
            }

            if (
                activeCommand_ ==
                ActiveCommand::OneDrive
            ) {
                parseOneDriveOutput(outputBuffer_);

                activeCommand_ = ActiveCommand::None;

                setControlsBusy(false);
                refreshButton_->setText(
                    QStringLiteral("Refresh")
                );

                healthBadgeLabel_->setText(
                    dashboardHealth_
                );

                lastUpdatedLabel_->setText(
                    QStringLiteral("Updated %1")
                        .arg(QDateTime::currentDateTime().toString(
                            QStringLiteral("HH:mm:ss")
                        ))
                );

                commandOutput_->appendPlainText(
                    QStringLiteral(
                        "[OK] Dashboard values updated."
                    )
                );

                return;
            }

            if (activeCommand_ == ActiveCommand::Profile) {
                activeCommand_ = ActiveCommand::None;
                setControlsBusy(false);
                refreshButton_->setText(QStringLiteral("Refresh"));
                healthBadgeLabel_->setText(QStringLiteral("Profile Applied"));

                QTimer::singleShot(
                    400,
                    this,
                    &MainWindow::refreshDashboard
                );
                return;
            }

            if (activeCommand_ == ActiveCommand::Generic) {
                activeCommand_ = ActiveCommand::None;
                setControlsBusy(false);
                refreshButton_->setText(QStringLiteral("Refresh"));
                healthBadgeLabel_->setText(
                    QStringLiteral("Command Complete")
                );
            }
        }
    );

    if (!qEnvironmentVariableIsSet("LABCTL_GUI_DISABLE_AUTO_REFRESH")) {
        QTimer::singleShot(
            250,
            this,
            &MainWindow::refreshDashboard
        );
    }
}

void MainWindow::refreshCurrentPage()
{
    showPage(currentPage_);
}

void MainWindow::showPage(const QString& page)
{
    if (labctlRunner_->isRunning()) {
        return;
    }

    currentPage_ = page;
    pageTitleLabel_->setText(page);

    if (pageIndexes_.contains(page)) {
        pageStack_->setCurrentIndex(pageIndexes_.value(page));
    }

    if (pageOutputs_.contains(page)) {
        commandOutput_ = pageOutputs_.value(page);
    }

    if (page == QStringLiteral("Dashboard")) {
        pageSubtitleLabel_->setText(
            QStringLiteral("System overview and laboratory services")
        );
        refreshDashboard();
    } else if (page == QStringLiteral("Monitor")) {
        pageSubtitleLabel_->setText(
            QStringLiteral("Detailed workstation resource summary")
        );
        runCommand({QStringLiteral("monitor"), QStringLiteral("summary")});
    } else if (page == QStringLiteral("Services")) {
        pageSubtitleLabel_->setText(
            QStringLiteral("Laboratory component and power state")
        );
        runCommand({QStringLiteral("profile"), QStringLiteral("status")});
    } else if (page == QStringLiteral("Workloads")) {
        pageSubtitleLabel_->setText(
            QStringLiteral("Containers and virtual machine inventory")
        );
        refreshDashboard();
    } else if (page == QStringLiteral("Network")) {
        pageSubtitleLabel_->setText(
            QStringLiteral("Network interfaces and traffic")
        );
        runCommand({QStringLiteral("monitor"), QStringLiteral("network")});
    } else if (page == QStringLiteral("Storage")) {
        pageSubtitleLabel_->setText(
            QStringLiteral("Filesystem capacity and disk activity")
        );
        runCommand({QStringLiteral("monitor"), QStringLiteral("disk")});
    } else if (page == QStringLiteral("Reports")) {
        pageSubtitleLabel_->setText(
            QStringLiteral("Read-only workstation diagnostic")
        );
        runCommand({QStringLiteral("doctor")});
    } else {
        pageSubtitleLabel_->setText(
            QStringLiteral("LabCTL installation and platform information")
        );
        runCommand({QStringLiteral("about")});
    }
}

void MainWindow::runServiceAction(
    const QString& module,
    const QString& action,
    const QString& serviceName)
{
    if (labctlRunner_->isRunning()) {
        QMessageBox::information(
            this,
            QStringLiteral("LabCTL is busy"),
            QStringLiteral("Wait for the current command or cancel it first.")
        );
        return;
    }

    if (action == QStringLiteral("status")) {
        runCommand({module, action});
        return;
    }

    const QMessageBox::StandardButton answer = QMessageBox::question(
        this,
        QStringLiteral("Confirm service action"),
        QStringLiteral("%1 %2?")
            .arg(action.left(1).toUpper() + action.mid(1), serviceName),
        QMessageBox::Yes | QMessageBox::No,
        QMessageBox::No
    );

    if (answer != QMessageBox::Yes) {
        return;
    }

    runCommand({module, action}, true);
}

void MainWindow::runProfileAction(const QString& profile)
{
    if (labctlRunner_->isRunning()) {
        return;
    }

    const QMessageBox::StandardButton answer = QMessageBox::warning(
        this,
        QStringLiteral("Apply workstation profile"),
        QStringLiteral(
            "Apply the '%1' profile? Components not included in the profile "
            "will be stopped. LabCTL will request authorization through KDE."
        ).arg(profile),
        QMessageBox::Yes | QMessageBox::No,
        QMessageBox::No
    );

    if (answer != QMessageBox::Yes) {
        return;
    }

    runCommand(
        {profile, QStringLiteral("--yes")},
        true,
        ActiveCommand::Profile
    );
}

void MainWindow::runCommand(
    const QStringList& arguments,
    bool usePolicyKit,
    ActiveCommand commandType)
{
    if (labctlRunner_->isRunning()) {
        return;
    }

    activeCommand_ = commandType;
    healthBadgeLabel_->setText(QStringLiteral("Running"));
    commandOutput_->clear();
    commandOutput_->appendPlainText(
        QStringLiteral("[INFO] Running LabCTL command...")
    );
    labctlRunner_->run(arguments, usePolicyKit);
}

void MainWindow::refreshDashboard()
{
    if (labctlRunner_->isRunning()) {
        return;
    }

    activeCommand_ = ActiveCommand::Dashboard;

    healthBadgeLabel_->setText(
        QStringLiteral("Refreshing")
    );

    commandOutput_->clear();
    commandOutput_->appendPlainText(
        QStringLiteral(
            "[INFO] Reading workstation status..."
        )
    );

    labctlRunner_->run({
        QStringLiteral("monitor"),
        QStringLiteral("dashboard"),
        QStringLiteral("--json")
    });
}

void MainWindow::runOneDriveStatus()
{
    if (labctlRunner_->isRunning()) {
        QTimer::singleShot(
            100,
            this,
            &MainWindow::runOneDriveStatus
        );
        return;
    }

    activeCommand_ = ActiveCommand::OneDrive;

    labctlRunner_->run({
        QStringLiteral("onedrive"),
        QStringLiteral("status")
    });
}

QString MainWindow::capturedValue(
    const QString& output,
    const QString& pattern)
{
    const QRegularExpression expression(
        pattern,
        QRegularExpression::MultilineOption |
        QRegularExpression::CaseInsensitiveOption
    );

    const QRegularExpressionMatch match =
        expression.match(output);

    if (!match.hasMatch()) {
        return {};
    }

    return match.captured(1).trimmed();
}

void MainWindow::parseDashboardOutput(
    const QString& output)
{
    QJsonParseError error;
    const QJsonDocument document = QJsonDocument::fromJson(
        output.toUtf8(),
        &error
    );
    if (error.error != QJsonParseError::NoError || !document.isObject()) {
        dashboardHealth_ = QStringLiteral("INVALID DATA");
        healthBadgeLabel_->setText(dashboardHealth_);
        alertsLabel_->setText(
            QStringLiteral("Dashboard JSON could not be parsed: %1")
                .arg(error.errorString())
        );
        return;
    }

    const QJsonObject root = document.object();
    if (root.value(QStringLiteral("schema_version")).toInt() != 1) {
        dashboardHealth_ = QStringLiteral("UNSUPPORTED DATA");
        healthBadgeLabel_->setText(dashboardHealth_);
        alertsLabel_->setText(QStringLiteral("Unsupported dashboard schema."));
        return;
    }

    const auto formatBytes = [](double bytes)
    {
        const QStringList units = {
            QStringLiteral("B"), QStringLiteral("KiB"),
            QStringLiteral("MiB"), QStringLiteral("GiB"),
            QStringLiteral("TiB")
        };
        int unit = 0;
        while (bytes >= 1024.0 && unit < units.size() - 1) {
            bytes /= 1024.0;
            ++unit;
        }
        return QStringLiteral("%1 %2")
            .arg(bytes, 0, 'f', unit == 0 ? 0 : 1)
            .arg(units.at(unit));
    };
    const auto number = [](const QJsonObject& object, const QString& key)
    {
        return object.value(key).isDouble()
            ? object.value(key).toDouble()
            : -1.0;
    };

    const QJsonObject resources = root.value(QStringLiteral("resources")).toObject();
    const QJsonObject cpu = resources.value(QStringLiteral("cpu")).toObject();
    const QJsonObject memory = resources.value(QStringLiteral("memory")).toObject();
    const QJsonObject gpu = resources.value(QStringLiteral("gpu")).toObject();
    const QJsonObject storage = resources.value(QStringLiteral("storage")).toObject();
    const double cpuUsage = number(cpu, QStringLiteral("usage_percent"));
    const double cpuTemperature = number(cpu, QStringLiteral("temperature_c"));
    const double memoryUsage = number(memory, QStringLiteral("usage_percent"));
    const double gpuUsage = number(gpu, QStringLiteral("usage_percent"));
    const double gpuTemperature = number(gpu, QStringLiteral("temperature_c"));
    const double storageUsage = number(storage, QStringLiteral("usage_percent"));

    cpuValueLabel_->setText(
        cpuUsage < 0
            ? QStringLiteral("--")
            : QStringLiteral("%1% · %2 °C").arg(cpuUsage, 0, 'f', 0)
                .arg(cpuTemperature, 0, 'f', 0)
    );
    memoryValueLabel_->setText(
        memoryUsage < 0
            ? QStringLiteral("--")
            : QStringLiteral("%1% · %2 / %3")
                .arg(memoryUsage, 0, 'f', 0)
                .arg(formatBytes(number(memory, QStringLiteral("used_bytes"))))
                .arg(formatBytes(number(memory, QStringLiteral("total_bytes"))))
    );
    gpuValueLabel_->setText(
        gpuUsage < 0
            ? QStringLiteral("Unavailable")
            : QStringLiteral("%1% · %2 °C").arg(gpuUsage, 0, 'f', 0)
                .arg(gpuTemperature, 0, 'f', 0)
    );
    storageValueLabel_->setText(
        storageUsage < 0
            ? QStringLiteral("--")
            : QStringLiteral("%1% · %2 free")
                .arg(storageUsage, 0, 'f', 0)
                .arg(formatBytes(number(storage, QStringLiteral("available_bytes"))))
    );

    profileValueLabel_->setText(root.value(QStringLiteral("profile")).toString());
    powerValueLabel_->setText(root.value(QStringLiteral("power_profile")).toString());
    const double battery = root.value(QStringLiteral("battery_percent")).toDouble(-1);
    batteryValueLabel_->setText(
        battery < 0 ? QStringLiteral("Unavailable")
                    : QStringLiteral("%1%").arg(battery, 0, 'f', 0)
    );

    const QJsonObject network = root.value(QStringLiteral("network")).toObject();
    const QString interface = network.value(QStringLiteral("interface")).toString();
    const double receiveRate = number(network, QStringLiteral("receive_bytes_per_second"));
    const double transmitRate = number(network, QStringLiteral("transmit_bytes_per_second"));
    networkValueLabel_->setText(
        interface.isEmpty()
            ? QStringLiteral("Unavailable")
            : QStringLiteral("%1 · ↓ %2/s ↑ %3/s")
                .arg(interface)
                .arg(formatBytes(std::max(0.0, receiveRate)))
                .arg(formatBytes(std::max(0.0, transmitRate)))
    );
    ipValueLabel_->setText(network.value(QStringLiteral("ipv4")).toString());
    vpnValueLabel_->setText(network.value(QStringLiteral("vpn")).toString().toUpper());

    const QJsonObject services = root.value(QStringLiteral("services")).toObject();
    setServiceStatus(dockerStatusLabel_, services.value(QStringLiteral("docker")).toString());
    setServiceStatus(libvirtStatusLabel_, services.value(QStringLiteral("libvirt")).toString());
    setServiceStatus(vmwareStatusLabel_, services.value(QStringLiteral("vmware")).toString());
    setServiceStatus(ollamaStatusLabel_, services.value(QStringLiteral("ollama")).toString());

    const QJsonObject workloads = root.value(QStringLiteral("workloads")).toObject();
    const QJsonObject running = workloads.value(QStringLiteral("running")).toObject();
    containersValueLabel_->setText(QString::number(running.value(QStringLiteral("containers")).toInt()));
    libvirtVmValueLabel_->setText(QString::number(running.value(QStringLiteral("libvirt")).toInt()));
    vmwareVmValueLabel_->setText(QString::number(running.value(QStringLiteral("vmware")).toInt()));
    virtualboxVmValueLabel_->setText(QString::number(running.value(QStringLiteral("virtualbox")).toInt()));

    workloadsTree_->clear();
    const QJsonArray workloadItems = workloads.value(QStringLiteral("items")).toArray();
    for (const QJsonValue& itemValue : workloadItems) {
        const QJsonObject item = itemValue.toObject();
        auto* row = new QTreeWidgetItem(workloadsTree_);
        row->setText(0, item.value(QStringLiteral("backend")).toString());
        row->setText(1, item.value(QStringLiteral("name")).toString());
        row->setText(2, item.value(QStringLiteral("state")).toString());
    }
    for (int column = 0; column < 3; ++column) {
        workloadsTree_->resizeColumnToContents(column);
    }

    QStringList alerts;
    const QJsonArray alertValues = root.value(QStringLiteral("alerts")).toArray();
    for (const QJsonValue& alertValue : alertValues) {
        const QJsonObject alert = alertValue.toObject();
        alerts.append(
            QStringLiteral("%1: %2")
                .arg(alert.value(QStringLiteral("severity")).toString().toUpper())
                .arg(alert.value(QStringLiteral("message")).toString())
        );
    }
    alertsLabel_->setText(
        alerts.isEmpty() ? QStringLiteral("No current alerts.")
                         : alerts.join(QStringLiteral("  ·  "))
    );

    dashboardHealth_ = root.value(QStringLiteral("health")).toString().toUpper();
    healthBadgeLabel_->setText(dashboardHealth_);
    QString badgeColors = QStringLiteral("background-color: #153e35; color: #6ee7b7;");
    if (dashboardHealth_ == QStringLiteral("WARNING")) {
        badgeColors = QStringLiteral("background-color: #422f16; color: #fbbf24;");
    } else if (dashboardHealth_ == QStringLiteral("CRITICAL")) {
        badgeColors = QStringLiteral("background-color: #4c1d1d; color: #fca5a5;");
    }
    healthBadgeLabel_->setStyleSheet(
        badgeColors + QStringLiteral(
            "padding: 8px 14px; border-radius: 8px; font-weight: 600;"
        )
    );

    if (cpuUsage >= 0) {
        cpuHistory_->addSample(cpuUsage);
    }
    if (memoryUsage >= 0) {
        memoryHistory_->addSample(memoryUsage);
    }
    if (cpuTemperature >= 0) {
        temperatureHistory_->addSample(cpuTemperature);
    }
    if (receiveRate >= 0 && transmitRate >= 0) {
        networkHistory_->addSample((receiveRate + transmitRate) / 1024.0);
    }

    const QDateTime timestamp = QDateTime::fromString(
        root.value(QStringLiteral("timestamp")).toString(),
        Qt::ISODate
    );
    if (timestamp.isValid()) {
        lastUpdatedLabel_->setText(
            QStringLiteral("Updated %1").arg(timestamp.toLocalTime().toString(
                QStringLiteral("HH:mm:ss")
            ))
        );
    }
}

void MainWindow::parseOneDriveOutput(
    const QString& output)
{
    const QString processState = capturedValue(
        output,
        QStringLiteral(
            R"(^Process State:\s+(RUNNING|STOPPED|ACTIVE|INACTIVE))"
        )
    );

    const QString serviceState = capturedValue(
        output,
        QStringLiteral(
            R"(^User Service:\s+(RUNNING|STOPPED|ACTIVE|INACTIVE))"
        )
    );

    if (
        processState.compare(
            QStringLiteral("RUNNING"),
            Qt::CaseInsensitive
        ) == 0 ||
        serviceState.compare(
            QStringLiteral("ACTIVE"),
            Qt::CaseInsensitive
        ) == 0
    ) {
        setServiceStatus(
            oneDriveStatusLabel_,
            QStringLiteral("RUNNING")
        );

        return;
    }

    if (!processState.isEmpty()) {
        setServiceStatus(
            oneDriveStatusLabel_,
            processState
        );

        return;
    }

    setServiceStatus(
        oneDriveStatusLabel_,
        serviceState
    );
}

void MainWindow::setServiceStatus(
    QLabel* label,
    const QString& status)
{
    if (label == nullptr) {
        return;
    }

    QString normalized =
        status.trimmed().toUpper();

    if (normalized.isEmpty()) {
        normalized = QStringLiteral("UNKNOWN");
    }

    const bool running =
        normalized == QStringLiteral("ACTIVE") ||
        normalized == QStringLiteral("RUNNING");

    if (running) {
        label->setText(QStringLiteral("Running"));

        label->setStyleSheet(
            QStringLiteral(
                "background-color: #153e35;"
                "color: #6ee7b7;"
                "padding: 5px 10px;"
                "border-radius: 7px;"
                "font-weight: 600;"
            )
        );

        return;
    }

    const bool stopped =
        normalized == QStringLiteral("STOPPED") ||
        normalized == QStringLiteral("INACTIVE");

    if (stopped) {
        label->setText(QStringLiteral("Stopped"));

        label->setStyleSheet(
            QStringLiteral(
                "background-color: #422026;"
                "color: #fca5a5;"
                "padding: 5px 10px;"
                "border-radius: 7px;"
                "font-weight: 600;"
            )
        );

        return;
    }

    label->setText(QStringLiteral("Unknown"));

    label->setStyleSheet(
        QStringLiteral(
            "background-color: #334155;"
            "color: #cbd5e1;"
            "padding: 5px 10px;"
            "border-radius: 7px;"
        )
    );
}
