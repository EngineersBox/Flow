module notcurses;

const usz ALPHA_HIGHCONTRAST = 0x30000000;
const usz ALPHA_TRANSPARENT = 0x20000000;
const usz ALPHA_BLEND = 0x10000000;
const usz ALPHA_OPAQUE = 0x00000000;

const ushort PALETTE_SIZE = 256;

const usz NOBACKGROUND_MASK = 0x8700000000000000;
const usz BGDEFAULT_MASK = 0x0000000040000000;
const usz BG_RGB_MASK = 0x0000000000ffffff;
const usz BG_PALETTE = 0x0000000008000000;
const usz BG_ALPHA_MASK = 0x30000000;

macro uint channel_initializer(char r, char g, char b) {
  return ((uint) r << 16) + ((uint) g << 8) + b + BGDEFAULT_MASK;
}

macro ulong channels_initializer(char fr, char fg, char fb, char br, char bg, char bb) {
    return (@channel_initializer(fr, fg, fb) << 32) + @channel_initializer(br, bg, bb);
}

macro uint channel_alpha(uint channel) {
    return channel & BG_ALPHA_MASK;
}

faultdef UNSUPPORTED_BG_ALPHA_FORMAT;

fn void? channel_set_alpha(uint* channel, uint alpha) {
    if (alpha & ~BG_ALPHA_MASK) {
        return UNSUPPORTED_BG_ALPHA_FORMAT?;
    }
    *channel = alpha | (*channel & (uint)~BG_ALPHA_MASK);
    if (alpha != ALPHA_OPAQUE) {
        *channel |- BGDEFAULT_MASK;
    }
}

macro bool channel_default_p(uint channel) {
    return !(channel & BGDEFAULT_MASK);
}

macro uint? channel_set_default(uint* channel) {
    *channel &= (uint)~BGDEFAULT_MASK;
    channel_set_alpha(channel, ALPHA_OPAQUE)!;
    return *channel;
}

macro bool channel_palindex_p(uint channel) {
    return !channel_default_p(channel) && (channel & BG_PALETTE);
}

macro uint channel_palindex(uint channel) {
    return channel & 0xff;
}

faultdef INVALID_PALETTE_INDEX;

fn void? channel_set_palindex(uint* channel, uint idx) {
    if (idx >= PALETTE_SIZE) {
        return INVALID_PALETTE_INDEX?;
    }
    channel_set_alpha(channel, ALPHA_OPAQUE)!;
    *channel &= 0xff000000;
    *channel |= BGDEFAULT_MASK | BG_PALETTE | idx;
}

macro bool channel_rgb_p(uint channel){
  return !(channel_default_p(channel) || channel_palindex_p(channel));
}

macro uint channel_r(uint channel) {
  return (channel & 0xff0000) >> 16u;
}

macro uint channel_g(uint channel) {
  return (channel & 0x00ff00) >> 8u;
}

macro uint channel_b(uint channel) {
  return (channel & 0x0000ff);
}

macro uint channel_rgb(uint channel) {
  return channel & BG_RGB_MASK;
}

<* @require r != g, g != b, r != b : "Pointers must be unique for each channel" *>
macro uint channel_rgb8(uint channel, uint* r, uint* g, uint* b) {
    *r = channel_r(channel);
    *g = channel_g(channel);
    *b = channel_b(channel);
    return channel;
}

faultdef EXCEEDED_CHANNEL_RANGE;

fn void? channel_set_rgb8(uint* channel, uint r, uint g, uint b) {
    if (r >= 256 || g >= 256 || b >= 256) {
        return EXCEEDED_CHANNEL_RANGE?;
    }
    uint c = (r << 16) | (g << 8) | b;
    *channel = (uint)((*channel & ~(BG_RGB_MASK | BG_PALETTE)) | BGDEFAULT_MASK | c);
}

fn void? channel_set(uint* channel, uint rgb) {
    if (rgb > 0xFFFFFF) {
        return EXCEEDED_CHANNEL_RANGE?;
    }
    *channel = (uint)((*channel & ~(BG_RGB_MASK | BG_PALETTE)) | BGDEFAULT_MASK | rgb);
}

fn void channel_set_rgb8_clipped(uint* channel, int r, int g, int b) {
	if(r >= 256){
		r = 255;
	}
	if(g >= 256){
		g = 255;
	}
	if(b >= 256){
		b = 255;
	}
	if(r <= -1){
		r = 0;
	}
	if(g <= -1){
		g = 0;
	}
	if(b <= -1){
		b = 0;
	}
    uint c = (r << 16) | (g << 8) | b;
    *channel = (uint)((*channel & ~(BG_RGB_MASK | BG_PALETTE)) | BGDEFAULT_MASK | c);
}

macro uint channels_bchannel(ulong channels) {
    return ((uint) channels) & (BG_RGB_MASK | BG_PALETTE | BGDEFAULT_MASK | BG_ALPHA_MASK);
}

macro uint channels_fchannel(ulong channels) {
    return channels_bchannel(channels >> 32);
}

macro ulong channels_channels(ulong channels) {
  return channels_bchannel(channels) | ((ulong) channels_fchannel(channels) << 32);
}

macro bool channels_bg_rgb_p(ulong channels) {
  return channel_rgb_p(channels_bchannel(channels));
}

macro bool channels_fg_rgb_p(ulong channels) {
  return channel_rgb_p(channels_fchannel(channels));
}

macro uint channels_bg_alpha(ulong channels) {
  return channel_alpha(channels_bchannel(channels));
}

macro ulong channels_set_bchannel(ulong* channels, uint channel) {
    *channels &= ((((ulong)0xffffffff) << 32) | NOBACKGROUND_MASK);
    *channels |= (uint) (channel & ~NOBACKGROUND_MASK);
    return *channels;
}

macro ulong channels_set_fchannel(ulong* channels, uint channel) {
    *channels &= (0xffffffff | ((ulong)NOBACKGROUND_MASK << 32));
    *channels |= (ulong) (channel & ~NOBACKGROUND_MASK) << 32;
    return *channels;
}

macro ulong channels_set_channels(ulong* dst, ulong channels) {
    channels_set_bchannel(dst, channels & 0xffffffff);
    channels_set_fchannel(dst, (uint) ((channels >> 32) & 0xffffffff));
    return *dst;
}

fn void? channels_set_bg_alpha(ulong* channels, uint alpha) {
    if (alpha == ALPHA_HIGHCONTRAST) {
        return UNSUPPORTED_BG_ALPHA_FORMAT?;
    }
    uint channel = channels_bchannel(*channels);
    channel_set_alpha(&channel, alpha)!;
    channels_set_bchannel(channels, channel);
}

macro uint channels_fg_alpha(ulong channels) {
    return channel_alpha(channels_fchannel(channels));
}

fn void? channels_set_fg_alpha(ulong* channels, uint alpha) {
    uint channel = channels_fchannel(*channels);
    channel_set_alpha(&channel, alpha)!;
    *channels = ((ulong) channel << 32) | (*channels & 0xffffffff);
}

fn ulong? channels_reverse(ulong channels) {
    ulong raw = ((ulong) channels_bchannel(channels) << 32) + channels_fchannel(channels);
    ulong statemask = ((NOBACKGROUND_MASK | BG_ALPHA_MASK) << 32u) |
                               NOBACKGROUND_MASK | BG_ALPHA_MASK;
    ulong ret = raw & ~statemask;
    ret |= channels & statemask;
    if (channels_bg_alpha(ret) != ALPHA_OPAQUE && !channels_bg_rgb_p(ret)) {
        channels_set_bg_alpha(&ret, ALPHA_OPAQUE)!;
    }
    if (channels_fg_alpha(ret) != ALPHA_OPAQUE && !channels_fg_rgb_p(ret)){
        channels_set_fg_alpha(&ret, ALPHA_OPAQUE)!;
    }
    return ret;
}
macro ulong channels_combine(uint fchan, uint bchan) {
	ulong channels = 0;
	channels_set_fchannel(&channels, fchan);
	channels_set_bchannel(&channels, bchan);
	return channels;
}

macro uint channels_fg_palindex(ulong channels) {
	return channel_palindex(channels_fchannel(channels));
}

macro uint channels_bg_palindex(ulong channels) {
	return channel_palindex(channels_bchannel(channels));
}

macro uint channels_fg_rgb(ulong channels) {
	return channel_rgb(channels_fchannel(channels));
}

macro uint channels_bg_rgb(ulong channels) {
	return channel_rgb(channels_bchannel(channels));
}

macro uint channels_fg_rgb8(ulong channels, uint* r, uint* g, uint* b) {
	return channel_rgb8(channels_fchannel(channels), r, g, b);
}

macro uint channels_bg_rgb8(ulong channels, uint* r, uint* g, uint* b) {
	return channel_rgb8(channels_bchannel(channels), r, g, b);
}

fn void? channels_set_fg_rgb8(ulong* channels, uint r, uint g, uint b) {
    uint channel = channels_fchannel(*channels);
    channel_set_rgb8(&channel, r, g, b)!;
    *channels = ((ulong) channel << 32) | (*channels & 0xffffffff);
}

fn void channels_set_fg_rgb8_clipped(ulong* channels, int r, int g, int b) {
    uint channel = channels_fchannel(*channels);
    channel_set_rgb8_clipped(&channel, r, g, b);
    *channels = ((ulong) channel << 32) | (*channels & 0xffffffff);
}

fn void? channels_set_fg_palindex(ulong* channels, uint idx) {
    uint channel = channels_fchannel(*channels);
    channel_set_palindex(&channel, idx)!;
    *channels = ((ulong) channel << 32) | (*channels & 0xffffffff);
}

fn void? channels_set_fg_rgb(ulong* channels, uint rgb) {
    uint channel = channels_fchannel(*channels);
    channel_set(&channel, rgb)!;
    *channels = ((ulong) channel << 32) | (*channels & 0xffffffff);
}

fn void? channels_set_bg_rgb8(ulong* channels, uint r, uint g, uint b) {
    uint channel = channels_bchannel(*channels);
    channel_set_rgb8(&channel, r, g, b)!;
    channels_set_bchannel(channels, channel);
}

fn void? channels_set_bg_rgb8_clipped(ulong* channels, int r, int g, int b) {
    uint channel = channels_bchannel(*channels);
    channel_set_rgb8_clipped(&channel, r, g, b);
    channels_set_bchannel(channels, channel);
}

fn void? channels_set_bg_palindex(ulong* channels, uint idx) {
    uint channel = channels_bchannel(*channels);
    channel_set_palindex(&channel, idx)!;
    channels_set_bchannel(channels, channel);
}

fn void? channels_set_bg_rgb(ulong* channels, uint rgb) {
    uint channel = channels_bchannel(*channels);
    channel_set(&channel, rgb)!;
    channels_set_bchannel(channels, channel);
}

macro bool channels_fg_default_p(ulong channels) {
    return channel_default_p(channels_fchannel(channels));
}

macro bool channels_fg_palindex_p(ulong channels) {
    return channel_palindex_p(channels_fchannel(channels));
}

macro bool channels_bg_default_p(ulong channels) {
    return channel_default_p(channels_bchannel(channels));
}

macro bool channels_bg_palindex_p(ulong channels) {
    return channel_palindex_p(channels_bchannel(channels));
}

fn ulong? channels_set_fg_default(ulong* channels) {
    uint channel = channels_fchannel(*channels);
    channel_set_default(&channel)!;
    channels_set_fchannel(channels, channel);
    return *channels;
}

fn ulong? channels_set_bg_default(ulong* channels) {
    uint channel = channels_bchannel(*channels);
    channel_set_default(&channel)!;
    channels_set_bchannel(channels, channel);
    return *channels;
}
