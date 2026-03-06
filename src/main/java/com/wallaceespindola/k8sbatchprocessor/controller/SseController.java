package com.wallaceespindola.k8sbatchprocessor.controller;

import com.wallaceespindola.k8sbatchprocessor.service.ProgressService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import lombok.RequiredArgsConstructor;
import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.CrossOrigin;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter;

@RestController
@RequestMapping("/api/sse")
@RequiredArgsConstructor
@Tag(name = "Server-Sent Events", description = "Real-time progress streaming via SSE")
@CrossOrigin(origins = "*")
public class SseController {

    private final ProgressService progressService;

    @GetMapping(value = "/progress", produces = MediaType.TEXT_EVENT_STREAM_VALUE)
    @Operation(summary = "Subscribe to batch progress events",
               description = "Opens an SSE stream that emits real-time progress events as accounts are processed")
    public SseEmitter subscribeProgress() {
        return progressService.subscribe();
    }
}
