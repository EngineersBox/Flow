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

faultdef INVALID_ALPHA;

fn void? channel_set_alpha(uint* channel, uint alpha) {
    if (alpha & ~BG_ALPHA_MASK) {
        return INVALID_ALPHA?;
    }
    *channel = alpha | (*channel & (uint)~BG_ALPHA_MASK);
    if (alpha != ALPHA_OPAQUE) {
        *channel |- BGDEFAULT_MASK;
    }
}

macro bool channel_default_p(uint channel) {
    return !(channel & BGDEFAULT_MASK);
}

macro uint channel_set_default(uint* channel) {
    *channel &= (uint)~BGDEFAULT_MASK;
    channel_set_alpha(channel, ALPHA_OPAQUE);
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

macro bool ncchannel_rgb_p(uint channel){
  return !(ncchannel_default_p(channel) || ncchannel_palindex_p(channel));
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
    return channels & (BG_RGB_MASK | BG_PALETTE | BGDEFAULT_MASK | BG_ALPHA_MASK);
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
    *channels &= ((0xffffffff << 32) | NOBACKGROUND_MASK);
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
