/*
 * Copyright (C) 1994-1998 T. Teranishi
 * (C) 2004- TeraTerm Project
 * All rights reserved.
 *
 * This file re-exports the shared TTLParser from TTLMacroShared.
 * The full implementation lives in Sources/TTLMacroShared/TTLParserShared.swift.
 *
 * All types (TTLParser, TTLError, TTLCommand, TTLVariable, etc.) are provided
 * by the TTLMacroShared module via the TeraTermMac target's dependency.
 * No additional declarations are needed here.
 */

@_exported import TTLMacroShared
