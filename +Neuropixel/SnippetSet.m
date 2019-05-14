classdef SnippetSet < handle & matlab.mixin.Copyable
    % A collection of snippets of data collected from an IMEC data file
    % which includes the subset of channels which were sampled
    
    % data here should be thought of as a set of data for many snippets
    % 
    
    properties
        ks % optional, handle to KilosortDataset for plotting waveforms and templates
        
        data (:, :, :, :) int16 % channels x time x snippets x layers
        cluster_ids (:, 1) uint32 % nSnippets x 1, array indicating which cluster is extracted in each snippet, if this makes sense. otherwise will just be 1s
        
        overlay_cluster_ids (:, 1) uint32 % set of clusters whose waveforms or templates will be drawn on top of a given snippet
        
        % for manually specifying overlay matrices (can also be generated automatically with e.g. overlay_waveforms)
        overlay_labels(:, :, :, :) uint32 % channels x time x snippets x layers (label matrix corresponding to elements of data for the purpose of generating colored overlays)
        overlay_datatip_label (1, 1) string
        overlay_datatip_values(:, 1) % nLabels x 1
        
        channel_ids_by_cluster (:, :) uint32 % nChannels x nClusters channel ids, which channel ids were extracted for each cluster
        unique_cluster_ids (:, 1) uint32 % specifies the cluster_ids associated with each column here
        
        sample_idx (:, 1) uint64
        trial_idx (:, 1) uint32
        window (:, 2) int64 % in samples
        
        valid (:, 1) logical
        
        channelMap % ChannelMap for coordinates
        scaleToUv (1, 1) double
        fs
    end
    
    properties(Dependent)
        nChannels
        nTimepoints
        nSnippets
        nClusters
        nLayers
        
        data_valid
        time_samples(:, 1) int64
        time_ms (:, 1) double
    end
    
    methods
        function ss = SnippetSet(ds, type)
            if nargin > 0
                if isa(ds, 'Neuropixel.KiloSortTrialSegmentedDataset')
                    raw_dataset = ds.raw_dataset;
                    ks = ds.dataset;
                elseif isa(ds, 'Neuropixel.KiloSortDataset')
                    raw_dataset = ds.raw_dataset;
                    ks = ds;
                elseif isa(ds, 'Neuropixel.ImecDataset')
                    raw_dataset = ds;
                    ks = [];
                else
                    error('Unknown arg type');
                end
                
                if nargin < 2 
                    type = 'ap';
                end
                switch type
                    case 'ap'
                        ss.scaleToUv = raw_dataset.apScaleToUv;
                        ss.fs = raw_dataset.fsAP;
                    case 'lf'
                        ss.scaleToUv = raw_dataset.lfScaleToUv;
                        ss.fs = raw_dataset.fsLF;
                    otherwise
                        error('Unknown type %s', type);
                end
                    
                 ss.channelMap = raw_dataset.channelMap;
                 ss.ks = ks;
            end
        end
        
        function n = get.nChannels(ss)
            n = size(ss.data, 1);
        end
        
        function n = get.nTimepoints(ss)
            n = size(ss.data, 2);
        end
        
        function n = get.nSnippets(ss)
            n = size(ss.data, 3);
        end
        
        function n = get.nLayers(ss)
            n = size(ss.data, 4);
        end
        
        function n = get.nClusters(ss)
            n = numel(ss.unique_cluster_ids);
        end
        
        function v = get.valid(ss)
            if isempty(ss.valid)
                v = true(size(ss.data, 3), 1);
            else
                v = ss.valid;
            end
        end
        
        function v = get.data_valid(ss)
            v = ss.data(:, :, ss.valid);
        end
        
        function v = get.time_ms(ss)
            v = double(ss.window(1) : ss.window(2)) / ss.fs * 1000;
        end
        
        function v = get.time_samples(ss)
            v = ss.window(1) : ss.window(2);
        end
  
        
        function colormap = generateOverlayColormap(~, overlay_labels, backgroundColor)
            if nargin < 3
                backgroundColor = [0 0 0; 1 1 1];
            end
            nLabels = max(overlay_labels(:));
            colormap = zeros(nLabels, 3);
            unique_labels = setdiff(unique(overlay_labels(:)), 0);
            label_found = ismember(1:nLabels, unique_labels);
            colormap(label_found, :) = Neuropixel.Utils.distinguishable_colors(nnz(label_found), backgroundColor);
        end
        
        function ss = selectClusters(ss, cluster_ids)
            mask = ismember(ss.cluster_ids, cluster_ids);
            ss = ss.selectData('maskSnippets', mask);
        end 
        
        function ss = selectData(ss, varargin)
            p = inputParser();
            p.addParameter('maskSnippets', ss.valid, @isvector);
            p.addParameter('maskTime', true(ss.nTimepoints, 1), @isvector);
            p.addParameter('maskChannels', true(ss.nChannels, 1), @isvector);
            p.parse(varargin{:});
            
            maskSnippets = p.Results.maskSnippets;
            
            ss = copy(ss);
            ss.valid = ss.valid(maskSnippets); % first time auto generates based on data, so has to come first
            ss.data = ss.data(p.Results.maskChannels, p.Results.maskTime, maskSnippets);
            
            if ~isempty(ss.overlay_labels)
                ss.overlay_labels = ss.overlay_labels(p.Results.maskChannels, p.Results.maskTime, maskSnippets);
            end
            
            ss.cluster_ids = ss.cluster_ids(maskSnippets);
        
            ss.sample_idx = ss.sample_idx(maskSnippets);
            if ~isempty(ss.trial_idx)
                ss.trial_idx = ss.trial_idx(maskSnippets);
            end
        end
        
        function [cluster_inds, cluster_ids] = lookup_clusterIds(ss, cluster_ids)
            if islogical(cluster_ids)
                cluster_ids = ss.unique_cluster_ids(cluster_ids);
            end
            [tf, cluster_inds] = ismember(cluster_ids, ss.unique_cluster_ids);
            assert(all(tf), 'Some cluster_ids not found in ss.unique_cluster_ids');
        end
        
        function [channelInds, channelIds] = lookup_channelIdsForSnippet(ss, snippetInd, channelIds)
            cluster_ind = ss.lookup_clusterIds(ss.cluster_ids(snippetInd));
            channel_ids_by_snippet = ss.channel_ids_by_cluster(cluster_ind, :);
            [tf, channelInds] = ismember(channelIds, channel_ids_by_snippet);
            assert(all(tf), 'Not all channel_ids found in ss.channel_ids_by_cluster for this snippet''s cluster');
        end
    end
    
    methods % plotting
        function hdata = plotAtProbeLocations(ss, varargin)
            p = inputParser();
            % specify one of these 
            p.addParameter('cluster_ids', [], @(x) isempty(x) || isvector(x));
            p.addParameter('maskSnippets', ss.valid, @isvector);
            
            % and optionally these
            p.addParameter('maskTime', true(ss.nTimepoints, 1), @isvector);
            p.addParameter('maskChannels', true(ss.nChannels, 1), @isvector);
            
            p.addParameter('maxPerCluster', Inf, @isscalar);
            
            p.addParameter('xmag', 1.5, @isscalar);
            p.addParameter('ymag', 1.5, @isscalar);
           
            p.addParameter('showIndividual', true, @islogical); 
            p.addParameter('showMean', false, @islogical);
            p.addParameter('meanPlotArgs', {'LineWidth', 3}, @iscell);
            p.addParameter('plotArgs', {'LineWidth', 0.5}, @iscell);
            
            p.addParameter('showChannelLabels', true, @islogical);
            p.addParameter('labelArgs', {}, @iscell);
            p.addParameter('alpha', 0.4, @isscalar);
            
            p.addParameter('colormap', get(groot, 'DefaultAxesColorOrder'), @(x) true);
            p.KeepUnmatched = false;
            p.parse(varargin{:});
            
            yspacing = ss.channelMap.yspacing;
            xspacing = ss.channelMap.xspacing;
            xmag = p.Results.xmag;
            ymag = p.Results.ymag;
            
            % plot relative time vector
            tvec = linspace(0, xspacing * xmag, numel(ss.window(1) : ss.window(2)));
            
            if ~isempty(p.Results.cluster_ids)
                maskSnippets = ismember(ss.cluster_ids, p.Results.cluster_ids) & ss.valid;
            else
                maskSnippets = p.Results.maskSnippets;
            end
           
            % center and scale each channel
            if ~any(maskSnippets)
                warning('No snippets for these clusters');
                return;
            end
            
            if isinteger(ss.data)
                data = single(ss.data(p.Results.maskChannels, p.Results.maskTime, maskSnippets));
            else
                data = ss.data(p.Results.maskChannels, p.Results.maskTime, maskSnippets);
            end
            data = data - mean(data(:, :), 2); %#ok<*PROPLC>
            data = data ./ (max(data(:)) - min(data(:))) * yspacing * ymag;
            
            cluster_ids = ss.cluster_ids(maskSnippets);
            unique_cluster_ids = unique(cluster_ids);
            nUniqueClusters = numel(unique_cluster_ids);
            
            holding = ishold;
            nChannels = size(data, 1);
            handlesIndiv = cell(nChannels, nUniqueClusters);
            handlesMean = gobjects(nChannels, nUniqueClusters);
            channels_plotted = false(ss.channelMap.nChannels, 1);
            
            cmap = p.Results.colormap;
            if isa(cmap, 'function_handle')
                cmap = cmap(nUniqueClusters);
            end
            
            for iClu = 1:nUniqueClusters
                this_cluster_ids = unique_cluster_ids(iClu);
                this_snippet_mask = cluster_ids == this_cluster_ids;
                [~, this_cluster_ind] = ismember(this_cluster_ids, ss.unique_cluster_ids);
                
                if isfinite(p.Results.maxPerCluster)
                    idxKeep = find(this_snippet_mask, p.Results.maxPerCluster, 'first');
                    this_snippet_mask(idxKeep(end)+1:end) = false;
                end
                
                this_channel_ids = ss.channel_ids_by_cluster(:, this_cluster_ind);
                this_channel_ids = this_channel_ids(p.Results.maskChannels);
                this_channel_inds = ss.channelMap.lookup_channelIds(this_channel_ids);
                xc = ss.channelMap.xcoords(this_channel_inds);
                yc = ss.channelMap.ycoords(this_channel_inds);
                
                channels_plotted(this_channel_inds) = true;

                cmapIdx = mod(iClu-1, size(cmap, 1))+1;
                
                for iC = 1:nChannels
                    dmat = Neuropixel.Utils.TensorUtils.squeezeDims(data(iC, :, this_snippet_mask), 1) + yc(iC);
                        
                    if p.Results.showIndividual
                        handlesIndiv{iC, iClu} = plot(tvec + xc(iC), dmat, 'Color', [cmap(cmapIdx, :), p.Results.alpha], ...
                            p.Results.plotArgs{:});
                        Neuropixel.Utils.hideInLegend(handlesIndiv{iC, iClu});
                        hold on;
                    end
                    if p.Results.showMean
                        handlesMean(iC, iClu) = plot(tvec + xc(iC), mean(dmat, 2), 'Color', cmap(cmapIdx, :), ...
                            p.Results.meanPlotArgs{:});
                        hold on;
                    end
                    if iC == 1 
                        Neuropixel.Utils.showFirstInLegend(handlesMean(iC, iClu), sprintf('cluster %d', this_cluster_ids));
                    else
                        Neuropixel.Utils.hideInLegend(handlesMean(iC, iClu));
                    end
                end
                
                %drawnow;
            end
            
            if p.Results.showChannelLabels
                xc = ss.channelMap.xcoords;
                yc = ss.channelMap.ycoords;
                
                for iC = 1:ss.channelMap.nChannels
                    if channels_plotted(iC)
                        text(xc(iC), yc(iC), sprintf('ch %d', ss.channelMap.channelIds(iC)), ...
                            'HorizontalAlignment', 'right', 'VerticalAlignment', 'middle', ...
                            p.Results.labelArgs{:});
                    end
                end
            end
            
            if ~holding
                hold off;
            end
            axis off;
            axis tight;
            box off;
            
            hdata.waveforms = handlesIndiv;
            hdata.waveformMeans = handlesMean;
        end
        
        function [bg, traceColor] = setupFigureAxes(~, dark)
            if dark
                bg = [16 16 16]/255;
                traceColor = 1 - bg;
                set(gcf, 'Color', bg);
                set(gca, 'Color', 'none');
            else
                bg = [1 1 1];
                traceColor = [0 0 0];
                set(gcf, 'Color', get(groot, 'DefaultFigureColor'));
                set(gca, 'Color', get(groot, 'DefaultAxesColor'));
            end
        end
        
        function [overlay_labels, overlay_datatip_label, overlay_datatip_values] = buildWaveformOverlays(ss, varargin)
            p = inputParser();
            p.addParameter('maskSnippets', ss.valid, @isvector);
            p.addParameter('cluster_ids', ss.overlay_cluster_ids, @isvector);
            p.addParameter('best_n_channels', 24, @isscalar);
            p.parse(varargin{:});
            
            assert(~isempty(ss.ks), 'KilosortDataset must be provided in .ks for waveform building');
            ks = ss.ks;
            
            channel_ids = ss.channel_ids_by_cluster;
            best_n_channels = p.Results.best_n_channels;
             
             m = ks.computeMetrics();
             [cluster_ind, cluster_ids] = ks.lookup_clusterIds(p.Results.cluster_ids);  

             % loop through all the extracted snippets, and for each cluster, find that cluster's spikes, and highlight the surrounding
             % waveform window by creating an overlay that matches the data within this window and is NaN elsewhere
                 
             cluster_best_channel_ids = m.cluster_best_channels(cluster_ind, 1:best_n_channels);

             snippet_inds = find(p.Results.maskSnippets);
             nSnippets = numel(snippet_inds);
             times = ss.sample_idx;
             labels = zeros(ss.nChannels, ss.nTimepoints, nSnippets, 1, 'uint32');
             
             for iiSn = 1:nSnippets
                 iSn = snippet_inds(iiSn);
                 % find all spike times in this window
                 this_window = int64(times(iSn)) + ss.window;
                 mask_spikes = ks.spike_times >= this_window(1) & ks.spike_times <= this_window(2);

                 % that belong to a cluster in cluster_ids
                 mask_spikes(mask_spikes) = ismember(ks.spike_clusters(mask_spikes), cluster_ids);

                 ind_spikes = find(mask_spikes);
                 selected_cluster_ids = ks.spike_clusters(mask_spikes);
                 [~, selected_cluster_inds] = ismember(selected_cluster_ids, cluster_ids);

                 % mark each spike in the labels matrix
                 for iSp = 1:numel(ind_spikes)
                    time_inds = ks.templateTimeRelative + int64(ks.spike_times(ind_spikes(iSp)))  - int64(times(iSn)) - int64(ss.window(1)) + int64(1);
                    % chop off time inds before and after window
                    mask = time_inds >= 1 & time_inds <= ss.nTimepoints;
                    time_inds = time_inds(mask);
                    
                    channel_ids_this = channel_ids(:, ss.cluster_ids(iSn));

                    [ch_included, ch_inds] = ismember(cluster_best_channel_ids(selected_cluster_inds(iSp), :), channel_ids_this);

                    labels(ch_inds(ch_included), time_inds, iSn) = selected_cluster_inds(iSp);
                 end
             end

             overlay_labels = labels;
             overlay_datatip_label = 'cluster';
             overlay_datatip_values = cluster_ids;
        end
        
        function [templates, template_start_ind, spike_inds, cluster_ids] = buildTemplateOverlays(ss, varargin)
            % temlates is ch x time x nTemplates reconstructed templates. the templates will be optionally nan'ed out at time
            % points that lie 
            
            p = inputParser();
            p.addParameter('maskSnippets', ss.valid, @isvector);
            p.addParameter('cluster_ids', ss.overlay_cluster_ids, @isvector);
            p.addParameter('best_n_channels', 24, @isscalar);
            p.addParameter('nanOutsideSnippet', true, @islogical);
            p.addParameter('nanOutsideBestChannels', true, @islogical);
             
            p.parse(varargin{:});
            
            assert(~isempty(ss.ks), 'KilosortDataset must be provided in .ks for waveform building');
            ks = ss.ks;
            
            nanOutsideSnippet = p.Results.nanOutsideSnippet;
            nanOutsideBestChannels = p.Results.nanOutsideBestChannels;
            
            if islogical(p.Results.maskSnippets)
                snippet_inds = find(p.Results.maskSnippets);
            else
                snippet_inds = p.Results.maskSnippets;
            end
             
            m = ks.computeMetrics();
            [cluster_ind, cluster_ids] = ks.lookup_clusterIds(p.Results.cluster_ids);  
            best_n_channels = p.Results.best_n_channels;       
            cluster_best_channel_ids = m.cluster_best_channels(cluster_ind, 1:best_n_channels);
             
            [templates, template_start_ind, spike_inds, cluster_ids_by_spike] = deal(cell(numel(snippet_inds), 1));
            for iiSn = 1:numel(snippet_inds)
                iSn = snippet_inds(iiSn);
                this_window = int64(ss.sample_idx(iSn)) + ss.window;
                cluster_ind_this = ss.lookup_clusterIds(ss.cluster_ids(iSn));
                ch_ids_this = ss.channel_ids_by_cluster(:, cluster_ind_this);
                 
                [spike_inds_this, template_start_inds_this, templates_this] = ...
                    ks.findSpikesOverlappingWithWindow(this_window, 'channel_ids', ch_ids_this, 'cluster_ids', cluster_ids);
                
                % templates_this is scaled to uv, but our data is unscaled
                templates_this = templates_this ./ ks.apScaleToUv;
                
                cluster_ids_this = ks.spike_clusters(spike_inds_this);
                % NaN out regions of the templates that are outside the plotting window or not on the best channels
                % template_this is C x T x nSpikes
                for iSp = 1:numel(spike_inds_this)
                    [~, cluster_ind_this] = ismember(cluster_ids_this(iSp), cluster_ids);
                    
                    if nanOutsideBestChannels
                        ch_mask_this = ismember(ch_ids_this, cluster_best_channel_ids(cluster_ind_this, :));
                        templates_this(~ch_mask_this, :, iSp) = NaN;
                    end
                    
                    if nanOutsideSnippet
                        template_tvec_this = template_start_inds_this(iSp)+int64(1:ks.nTemplateTimepoints);
                        t_mask_this = template_tvec_this >= 1 & template_tvec_this <= ss.nTimepoints;
                        templates_this(:, ~t_mask_this, iSp) = NaN;
                    end 
                end
                
                mask_templates = squeeze(any(~isnan(templates_this), [1 2]));  
                spike_inds{iiSn} = spike_inds_this(mask_templates);
                template_start_ind{iiSn} = template_start_inds_this(mask_templates);
                templates{iiSn} = templates_this(:, :, mask_templates);
                cluster_ids_by_spike{iiSn} = cluster_ids_this(mask_templates);
            end
            
            spike_inds = cat(1, spike_inds{:});
            template_start_ind = cat(1, template_start_ind{:});
            templates = cat(3, templates{:});
            cluster_ids = cat(1, cluster_ids_by_spike{:});
        end 
        
        function [recon, cluster_ids] = buildTemplateReconstructions(ss, varargin)
            [templates, template_start_ind, spike_inds, cluster_ids] = ss.buildTemplateOverlays(varargin{:});
            
            recon = zeros(ss.nChannels, ss.nTimepoints, size(templates, 3), 'like', ss.data);
            nTemplateTime = size(templates, 2);
            for iSp = 1:numel(spike_inds)
                insert_idx = int64(template_start_ind(iSp)) + int64(0:nTemplateTime-1);
                take_mask = insert_idx >= int64(1) & insert_idx <= size(recon, 2);
                insert_idx = insert_idx(take_mask);
                
                recon(:, insert_idx, iSp) = templates(:, take_mask, iSp); 
            end
        end
       
        function plotStackedTraces(ss, varargin)
            p = inputParser();
            p.addParameter('maskSnippets', ss.valid, @isvector);
            p.addParameter('showLabels', true, @islogical);
            p.addParameter('gain', 1.95, @isscalar);
%             p.addParameter('car', false, @islogical);
%             p.addParameter('downsample',1, @isscalar); 
            p.addParameter('timeInMilliseconds', false, @islogical);
            p.addParameter('dark', false, @islogical);
            p.addParameter('showChannelDataTips', false, @islogical);
            p.addParameter('showOverlayDataTips', true, @islogical);
            p.addParameter('showTemplateDataTips', true, @islogical);
            
            p.addParameter('overlay_waveforms', false, @islogical);
            p.addParameter('overlay_templates', false, @islogical);
            p.addParameter('overlay_cluster_ids', ss.overlay_cluster_ids, @isvector);
            p.addParameter('overlay_best_channels', 24, @isscalar);

            p.parse(varargin{:});
            
            dark = p.Results.dark;
            [bg, traceColor] = ss.setupFigureAxes(dark);

            if p.Results.timeInMilliseconds
                time = ss.time_ms;
            else
                time = ss.time_samples;
            end
            mask_snippets = p.Results.maskSnippets;

            data = ss.data(:, :, mask_snippets, :);
            
            overlay_cluster_ids = p.Results.overlay_cluster_ids;
            if isempty(overlay_cluster_ids) && ~isempty(ss.ks)
                % overlay all clusters if none specified
                overlay_cluster_ids = ss.ks.cluster_ids;
            end
            overlay_best_channels = p.Results.overlay_best_channels;
            overlay_cluster_colormap = ss.generateOverlayColormap(1:numel(overlay_cluster_ids), [bg; traceColor]);
            if p.Results.overlay_waveforms
                [overlay_labels, overlay_datatip_label, overlay_datatip_values] = ss.buildWaveformOverlays('maskSnippets', mask_snippets, ...
                    'cluster_ids', overlay_cluster_ids, ...
                    'best_n_channels', overlay_best_channels);
                overlay_colormap = overlay_cluster_colormap;
                
            elseif ~isempty(ss.overlay_labels)
                overlay_labels = ss.overlay_labels(:, :, mask_snippets, :);
                overlay_datatip_label = ss.overlay_datatip_label;
                overlay_datatip_values = ss.overlay_datatip_values;
                
                overlay_colormap = ss.generateOverlayColormap(overlay_labels, [bg; traceColor]);
            else
                [overlay_labels, overlay_datatip_label, overlay_datatip_values] = deal([]);
                overlay_colormap = [];
            end
            
            % not supported by waveform or template overlays yet
%             if p.Results.downsample > 1
%                 data = data(:, 1:p.Results.downsample:end, :, :);
%                 overlay_labels = overlay_labels(:, 1:p.Results.downsample:end, :, :);
%                 time = time(1:p.Results.downsample:end);
%             end
            
            % nCh x nSnippets
            cluster_inds_by_snippet = ss.lookup_clusterIds(ss.cluster_ids(mask_snippets));
            channel_ids_ch_by_snippet = ss.channel_ids_by_cluster(:, cluster_inds_by_snippet);
            
            % not supported by waveform or template overlays yet
%             if p.Results.car
%                 data = data - median(data, 1);
%             end
            
            % data is ch x time x snippets x layers
            % plot stacked traces wants time x ch x layers
            data_txcxl = permute(data(:, :, :), [2 1 3]);
            overlay_labels_txcxl = permute(overlay_labels(:, :, :), [2 1 3]);
            
            [~, transform] = Neuropixel.Utils.plotStackedTraces(time, data_txcxl, 'colors', traceColor, ...
                'gain', p.Results.gain, 'invertChannels', ss.channelMap.invertChannelsY, 'normalizeEach', false, ...
                'colorOverlayLabels', overlay_labels_txcxl, 'colorOverlayMap', overlay_colormap, ...
                'channel_ids', channel_ids_ch_by_snippet, 'showChannelDataTips', p.Results.showChannelDataTips, ...
                'showOverlayDataTips', p.Results.showOverlayDataTips, ...
                'colorOverlayDataTipLabel', overlay_datatip_label, 'colorOverlayDataTipValues', overlay_datatip_values);
            
            % plot templates if requested
            if p.Results.overlay_templates
                [templates, template_start_ind, spike_inds, cluster_ids] = ss.buildTemplateOverlays('maskSnippets', mask_snippets, ...
                    'cluster_ids', overlay_cluster_ids, ...
                    'best_n_channels', p.Results.overlay_best_channels);
                
                [~, cluster_inds] = ismember(cluster_ids, overlay_cluster_ids);
                
                % generate expanded time vector we can insert templates into accounting for timepoints outside the snippet
                % where a template could start
                nTemplateTime = size(templates, 2);
                time_exp =  int64(ss.window(1) + 1) - int64(nTemplateTime) : int64(ss.window(2) - 1) + int64(nTemplateTime);
                if p.Results.timeInMilliseconds
                    time_exp = single(time_exp) / ss.fs * 1000;
                end
                
                for iSp = 1:numel(spike_inds)
                    % template_start_ind corresponds to time, so we shift our start index to the right to account for the "pre-snippet"
                    % times we included in time_exp
                    time_this = time_exp( int64(template_start_ind(iSp)) + int64(nTemplateTime-1) + int64(0:nTemplateTime-1));
                    template_this = templates(:, :, iSp);
                    t_mask = any(~isnan(template_this), 1);
                    cluster_ind_this = cluster_inds(iSp);
                    if p.Results.showTemplateDataTips
                        dataTipArgs = {'dataTipLabel', 'cluster template', 'dataTipValues', cluster_ids(iSp), 'dataTipFormat', '%d'};
                    else
                        dataTipArgs = {};
                    end
                    hold on;
                    Neuropixel.Utils.plotStackedTraces(time_this(t_mask), template_this(:, t_mask)', ...
                        'colors', overlay_cluster_colormap(cluster_ind_this, :), ...
                        'transformInfo', transform, ...
                        dataTipArgs{:});
                end
            end
            axis off;
            hold off;
        end
        
        function plotHeatmapWithTemplates(ss, snippet_ind, varargin)
            % plots one snippet as a heatmap with each of the clusters that occur during that period
            
            p = inputParser();
            p.addParameter('timeInMilliseconds', false, @islogical);
            p.addParameter('reconstruct_cluster_ids', ss.overlay_cluster_ids, @isvector);
            p.addParameter('reconstruct_best_channels', 24, @isscalar);

            p.parse(varargin{:});
            
            if p.Results.timeInMilliseconds
                time = ss.time_ms;
            else
                time = ss.time_samples;
            end
            data = ss.data(:, :, snippet_ind, 1);
            
            reconstruct_cluster_ids = p.Results.reconstruct_cluster_ids;
            if isempty(reconstruct_cluster_ids) && ~isempty(ss.ks)
                % overlay all clusters if none specified
                reconstruct_cluster_ids = ss.ks.cluster_ids;
            end
            reconstruct_best_channels = p.Results.reconstruct_best_channels;
            
            % nCh x nSnippets
%             cluster_inds_by_snippet = ss.lookup_clusterIds(ss.cluster_ids(snippet_ind));
%             channel_ids_ch_by_snippet = ss.channel_ids_by_cluster(:, cluster_inds_by_snippet);
            
             [templates, cluster_ids] = ss.buildTemplateReconstructions('maskSnippets', snippet_ind, ...
                'cluster_ids', reconstruct_cluster_ids, ...
                'best_n_channels', reconstruct_best_channels);
            
            templates_stacked = Neuropixel.Utils.TensorUtils.reshapeByConcatenatingDims(templates, {[1 3], 2});
            data_stacked = cat(1, data, templates_stacked);
            
            pmatbal(data_stacked);
            C = ss.nChannels;
            h = yline(0.5, '-', sprintf('snippet %d', snippet_ind), 'LabelVerticalAlignment', 'bottom');
            for iC = 1:size(templates, 3)
                yline(ss.nChannels * iC + 0.5, 'k-', sprintf('cluster %u', cluster_ids(iC)), 'LabelVerticalAlignment', 'bottom');
            end
        end
    end
end