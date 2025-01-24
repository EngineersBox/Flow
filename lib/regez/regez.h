#pragma once

#ifndef __REGEZ_H_
#define __REGEZ_H_

#include <regex.h>
#include <stdalign.h>

const size_t sizeof_regex_t = sizeof(regex_t);
const size_t alignof_regex_t = alignof(regex_t);

#endif // __REGEZ_H_
