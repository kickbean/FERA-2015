function Script_HOG_SVR_train()

% Change to your downloaded location
addpath('C:\liblinear\matlab')

%% load shared definitions and AU data
shared_defs;

% Set up the hyperparameters to be validated
hyperparams.c = 10.^(-7:0.5:1);
hyperparams.p = 10.^(-2);

hyperparams.validate_params = {'c', 'p'};

% Set the training function
svm_train = @svm_train_linear;
    
% Set the test function (the first output will be used for validation)
svm_test = @svm_test_linear;

pca_loc = '../pca_generation/generic_face_rigid.mat';

%%
for a=1:numel(all_aus_int)
    
    au = all_aus_int(a);
            
    % load the training and testing data for the current fold
    [train_samples, train_labels, vid_ids_train, valid_samples, valid_labels, vid_ids_valid, raw_valid, PC, means, scaling] = Prepare_HOG_AU_data_generic_intensity(train_recs, devel_recs, au, BP4D_dir_int, hog_data_dir, pca_loc);

    train_samples = sparse(train_samples);
    valid_samples = sparse(valid_samples);

    %% Cross-validate here                
    [ best_params, all_params ] = validate_grid_search(svm_train, svm_test, false, train_samples, train_labels, valid_samples, valid_labels, hyperparams);

    model = svm_train(train_labels, train_samples, best_params);        

    [prediction, a, actual_vals] = predict(valid_labels, valid_samples, model);
    
    prediction(prediction < 0) = 0;
    prediction(prediction > 5) = 5;
    
    % Go from raw data to the prediction
    w = model.w(1:end-1)';
    b = model.w(end);

    svs = bsxfun(@times, PC, 1./scaling') * w;

    % Attempt own prediction
    preds_mine = bsxfun(@plus, raw_valid, -means) * svs + b;

    assert(norm(preds_mine - actual_vals) < 1e-8);

    name = sprintf('new_tracker/AU_%d_static_intensity.dat', au);
    write_lin_svr(name, means, svs, b);

    name = sprintf('new_tracker/AU_%d_static_intensity.mat', au);
    
    correlation = corr(valid_labels, prediction);
    RMSE = sqrt(mean((valid_labels - prediction).^2));
    
    % convert to binary as well (to compare)    
    [~, ~, valid_samples_bin, valid_labels_bin] = Prepare_HOG_AU_data_generic(train_recs, devel_recs, au, BP4D_dir, hog_data_dir, pca_loc);    
    
    [prediction, a, actual_vals] = predict(valid_labels_bin, sparse(valid_samples_bin), model);
    
    prediction_bin = prediction > 1;
        
    tp = sum(valid_labels_bin == 1 & prediction_bin == 1);
    fp = sum(valid_labels_bin == 0 & prediction_bin == 1);
    fn = sum(valid_labels_bin == 1 & prediction_bin == 0);
    tn = sum(valid_labels_bin == 0 & prediction_bin == 0);

    precision = tp/(tp+fp);
    recall = tp/(tp+fn);

    f1 = 2 * precision * recall / (precision + recall);    
        
    %%
    save(name, 'model', 'correlation', 'RMSE', 'f1', 'precision', 'recall');
        
end

end

function [model] = svm_train_linear(train_labels, train_samples, hyper)
    comm = sprintf('-s 11 -B 1 -p %.10f -c %.10f -q', hyper.p, hyper.c);
    model = train(train_labels, train_samples, comm);
end

function [result, prediction] = svm_test_linear(test_labels, test_samples, model)

    prediction = predict(test_labels, test_samples, model);
    prediction(prediction<0)=0;
    prediction(prediction>5)=5;
    % using the average of RMS errors
%     result = mean(sqrt(mean((prediction - test_labels).^2)));  
    result = corr(test_labels, prediction);
    if(isnan(result))
        result = 0;
    end
    
end
