#pragma once

// Independently restated QTFB wire ABI from asivery/rm-appload v0.5.3
// (5bb34a362f09f753f18bd6261558f8e2737aacdb), GPL-3.0. The same ABI is
// already adapted by KOReader base/ffi-cdecl/include/qtfb.h (AGPL-3.0).

#include <cstddef>
#include <cstdint>

namespace paperpro::qtfb {

using FramebufferKey = int;

enum MessageType : std::uint8_t {
    Initialize = 0,
    Update = 1,
    CustomInitialize = 2,
    Terminate = 3,
    UserInput = 4,
    SetRefreshMode = 5,
    RequestFullRefresh = 6,
};

enum RefreshMode : int {
    UFast = 0,
    Fast = 1,
    Animate = 2,
    Content = 3,
    Ui = 4,
};

struct InitMessageContents {
    FramebufferKey framebuffer_key;
    std::uint8_t framebuffer_type;
};

struct CustomInitMessageContents {
    FramebufferKey framebuffer_key;
    std::uint8_t framebuffer_type;
    std::uint16_t width;
    std::uint16_t height;
};

struct UpdateRegionMessageContents {
    int type;
    int x;
    int y;
    int width;
    int height;
};

struct ClientMessage {
    std::uint8_t type;
    union {
        InitMessageContents init;
        UpdateRegionMessageContents update;
        CustomInitMessageContents custom_init;
        int refresh_mode;
    };
};

struct InitMessageResponseContents {
    int shared_memory_key;
    std::size_t shared_memory_size;
};

struct UserInputContents {
    int input_type;
    int device_id;
    int x;
    int y;
    int detail;
};

struct ServerMessage {
    std::uint8_t type;
    union {
        InitMessageResponseContents init;
        UserInputContents user_input;
    };
};

static_assert(sizeof(ClientMessage) == 24, "QTFB LP64 ClientMessage ABI changed");
static_assert(sizeof(ServerMessage) == 32, "QTFB LP64 ServerMessage ABI changed");

} // namespace paperpro::qtfb
