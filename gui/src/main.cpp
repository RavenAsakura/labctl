#include "MainWindow.hpp"

#include <QApplication>
#include <QCoreApplication>
#include <QFile>
#include <QTextStream>

namespace
{
QString loadStyleSheet()
{
    QFile styleFile(QStringLiteral(":/themes/dark.qss"));

    if (!styleFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
        return {};
    }

    QTextStream stream(&styleFile);
    return stream.readAll();
}
}

int main(int argc, char* argv[])
{
    QApplication application(argc, argv);

    QCoreApplication::setApplicationName(QStringLiteral("LabCTL"));
    QCoreApplication::setApplicationVersion(QStringLiteral("0.3.0"));
    QCoreApplication::setOrganizationName(QStringLiteral("LabCTL"));

    application.setStyleSheet(loadStyleSheet());

    MainWindow window;
    window.show();

    return QApplication::exec();
}
