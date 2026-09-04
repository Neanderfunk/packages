cmake_minimum_required(VERSION 3.13)

project(NODEPLACER C)

set_property(DIRECTORY PROPERTY COMPILE_DEFINITIONS _GNU_SOURCE)

find_path(UBOX_INCLUDE_DIR NAMES libubox/uloop.h)
find_library(UBOX_LIBRARY NAMES ubox)
find_library(UCLIENT_LIBRARY NAMES uclient)
find_library(UCI_LIBRARY NAMES uci)
find_library(GLUONUTIL_LIBRARY NAMES gluonutil)

find_package(PkgConfig REQUIRED QUIET)
pkg_check_modules(ECDSAUTIL REQUIRED ecdsautil)
pkg_check_modules(JSONC REQUIRED json-c)

include_directories(${UBOX_INCLUDE_DIR} ${ECDSAUTIL_INCLUDE_DIRS} ${JSONC_INCLUDE_DIRS})

# nodeplacer-fetch: download + verify, derived from the autoupdater
add_executable(nodeplacer-fetch
  fetch.c
  hexutil.c
  manifest.c
  uclient.c
  util.c
)
set_property(TARGET nodeplacer-fetch PROPERTY COMPILE_FLAGS "-std=c99 -Wall")
target_link_libraries(nodeplacer-fetch
  ${UCI_LIBRARY}
  ${UBOX_LIBRARY}
  ${UCLIENT_LIBRARY}
  ${ECDSAUTIL_LIBRARIES}
)

install(TARGETS nodeplacer-fetch RUNTIME DESTINATION sbin)

# respondd provider; gluon.mk expects $(PKG_BUILD_DIR)/respondd.so
add_library(respondd MODULE respondd.c)
set_target_properties(respondd PROPERTIES
  PREFIX ""
  COMPILE_FLAGS "-Wall"
  LIBRARY_OUTPUT_DIRECTORY ${CMAKE_SOURCE_DIR}
)
target_link_libraries(respondd
  ${UCI_LIBRARY}
  ${GLUONUTIL_LIBRARY}
  ${JSONC_LIBRARIES}
)
