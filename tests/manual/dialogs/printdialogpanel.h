/****************************************************************************
**
** Copyright (C) 2021 The Qt Company Ltd.
** Contact: https://www.qt.io/licensing/
**
** This file is part of the test suite of the Qt Toolkit.
**
** $QT_BEGIN_LICENSE:GPL-EXCEPT$
** Commercial License Usage
** Licensees holding valid commercial Qt licenses may use this file in
** accordance with the commercial license agreement provided with the
** Software or, alternatively, in accordance with the terms contained in
** a written agreement between you and The Qt Company. For licensing terms
** and conditions see https://www.qt.io/terms-conditions. For further
** information use the contact form at https://www.qt.io/contact-us.
**
** GNU General Public License Usage
** Alternatively, this file may be used under the terms of the GNU
** General Public License version 3 as published by the Free Software
** Foundation with exceptions as appearing in the file LICENSE.GPL3-EXCEPT
** included in the packaging of this file. Please review the following
** information to ensure the GNU General Public License requirements will
** be met: https://www.gnu.org/licenses/gpl-3.0.html.
**
** $QT_END_LICENSE$
**
****************************************************************************/

#ifndef PRINTDIALOGPANEL_H
#define PRINTDIALOGPANEL_H

#ifndef QT_NO_PRINTER

#include "ui_printdialogpanel.h"

#include <QPageLayout>
#include <QPrinter>
#include <QWidget>

QT_BEGIN_NAMESPACE
class QPrinter;
class QComboBox;
class QGroupBox;
class QPushButton;
class QCheckBox;
QT_END_NAMESPACE

class PageSizeControl;
class OptionsControl;

class PrintDialogPanel  : public QWidget
{
    Q_OBJECT
public:
    explicit PrintDialogPanel(QWidget *parent = nullptr);
    ~PrintDialogPanel();

private slots:
    void createPrinter();
    void deletePrinter();
    void showPrintDialog();
    void showPreviewDialog();
    void showPageSetupDialog();
    void directPrint();
    void unitsChanged();
    void pageSizeChanged();
    void pageDimensionsChanged();
    void orientationChanged();
    void marginsChanged();
    void layoutModeChanged();
    void printerChanged();

private:
    QSizeF customPageSize() const;
    void applySettings(QPrinter *printer) const;
    void retrieveSettings(const QPrinter *printer);
    void updatePageLayoutWidgets();
    void enablePanels();

    bool m_blockSignals;
    Ui::PrintDialogPanel m_panel;

    QPageLayout m_pageLayout;
    QScopedPointer<QPrinter> m_printer;
};

#endif // !QT_NO_PRINTER
#endif // PRINTDIALOGPANEL_H
