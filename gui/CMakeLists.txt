cmake_minimum_required(VERSION 3.21)

project(
    LabCTLGui
    VERSION 0.3.0
    DESCRIPTION "Native graphical interface for LabCTL"
    LANGUAGES CXX
)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTOUIC ON)
set(CMAKE_AUTORCC ON)

include(CTest)

set(
    CMAKE_AUTOUIC_SEARCH_PATHS
    "${CMAKE_CURRENT_SOURCE_DIR}/ui"
)

find_package(
    Qt6 6.4 REQUIRED
    COMPONENTS
        Core
        Gui
        Widgets
)

if(BUILD_TESTING)
    find_package(Qt6 6.4 REQUIRED COMPONENTS Test)
endif()

qt_standard_project_setup()

qt_add_executable(
    labctl-gui

    src/main.cpp
    src/MainWindow.cpp
    src/LabctlRunner.cpp
    src/MetricHistoryWidget.cpp

    include/MainWindow.hpp
    include/LabctlRunner.hpp
    include/MetricHistoryWidget.hpp

    ui/MainWindow.ui
    resources/resources.qrc
)

target_include_directories(
    labctl-gui
    PRIVATE
        "${CMAKE_CURRENT_SOURCE_DIR}/include"
)

target_link_libraries(
    labctl-gui
    PRIVATE
        Qt6::Core
        Qt6::Gui
        Qt6::Widgets
)

target_compile_options(
    labctl-gui
    PRIVATE
        -Wall
        -Wextra
        -Wpedantic
)

install(
    TARGETS labctl-gui
    RUNTIME DESTINATION bin
)

if(BUILD_TESTING)
    add_subdirectory(tests)
endif()
