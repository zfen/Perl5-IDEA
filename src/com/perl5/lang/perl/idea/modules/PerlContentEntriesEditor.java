/*
 * Copyright 2015 Alexandr Evstigneev
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package com.perl5.lang.perl.idea.modules;

import com.intellij.ide.util.projectWizard.importSources.JavaModuleSourceRoot;
import com.intellij.ide.util.projectWizard.importSources.JavaSourceRootDetectionUtil;
import com.intellij.openapi.module.Module;
import com.intellij.openapi.progress.ProgressIndicator;
import com.intellij.openapi.progress.ProgressManager;
import com.intellij.openapi.progress.util.ProgressWindow;
import com.intellij.openapi.progress.util.SmoothProgressAdapter;
import com.intellij.openapi.project.Project;
import com.intellij.openapi.project.ProjectBundle;
import com.intellij.openapi.roots.ContentEntry;
import com.intellij.openapi.roots.ModifiableRootModel;
import com.intellij.openapi.roots.ui.configuration.CommonContentEntriesEditor;
import com.intellij.openapi.roots.ui.configuration.ContentEntryEditor;
import com.intellij.openapi.roots.ui.configuration.JavaContentEntryEditor;
import com.intellij.openapi.roots.ui.configuration.ModuleConfigurationState;
import com.intellij.openapi.util.registry.Registry;
import com.intellij.openapi.vfs.LocalFileSystem;
import com.intellij.openapi.vfs.VfsUtilCore;
import com.intellij.openapi.vfs.VirtualFile;
import com.intellij.util.concurrency.SwingWorker;
import org.jetbrains.annotations.NotNull;
import org.jetbrains.jps.model.java.JavaSourceRootType;

import javax.swing.*;
import java.awt.*;
import java.io.File;
import java.util.Collection;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Created by hurricup on 07.06.2015.
 */
public class PerlContentEntriesEditor extends CommonContentEntriesEditor
{
	public PerlContentEntriesEditor(String moduleName, ModuleConfigurationState state)
	{
		super(moduleName, state, JavaSourceRootType.SOURCE, JavaSourceRootType.TEST_SOURCE);
	}

	private static void addSourceRoots(@NotNull Project project, final ContentEntry[] contentEntries, final Runnable finishRunnable)
	{
		final HashMap<ContentEntry, Collection<JavaModuleSourceRoot>> entryToRootMap = new HashMap<ContentEntry, Collection<JavaModuleSourceRoot>>();
		final Map<File, ContentEntry> fileToEntryMap = new HashMap<File, ContentEntry>();
		for (final ContentEntry contentEntry : contentEntries)
		{
			final VirtualFile file = contentEntry.getFile();
			if (file != null)
			{
				entryToRootMap.put(contentEntry, null);
				fileToEntryMap.put(VfsUtilCore.virtualToIoFile(file), contentEntry);
			}
		}

		final ProgressWindow progressWindow = new ProgressWindow(true, project);
		final ProgressIndicator progressIndicator = new SmoothProgressAdapter(progressWindow, project);

		final Runnable searchRunnable = new Runnable()
		{
			@Override
			public void run()
			{
				final Runnable process = new Runnable()
				{
					@Override
					public void run()
					{
						for (final File file : fileToEntryMap.keySet())
						{
							progressIndicator.setText(ProjectBundle.message("module.paths.searching.source.roots.progress", file.getPath()));
							final Collection<JavaModuleSourceRoot> roots = JavaSourceRootDetectionUtil.suggestRoots(file);
							entryToRootMap.put(fileToEntryMap.get(file), roots);
						}
					}
				};
				progressWindow.setTitle(ProjectBundle.message("module.paths.searching.source.roots.title"));
				ProgressManager.getInstance().runProcess(process, progressIndicator);
			}
		};

		final Runnable addSourcesRunnable = new Runnable()
		{
			@Override
			public void run()
			{
				for (final ContentEntry contentEntry : contentEntries)
				{
					final Collection<JavaModuleSourceRoot> suggestedRoots = entryToRootMap.get(contentEntry);
					if (suggestedRoots != null)
					{
						for (final JavaModuleSourceRoot suggestedRoot : suggestedRoots)
						{
							final VirtualFile sourceRoot = LocalFileSystem.getInstance().findFileByIoFile(suggestedRoot.getDirectory());
							final VirtualFile fileContent = contentEntry.getFile();
							if (sourceRoot != null && fileContent != null && VfsUtilCore.isAncestor(fileContent, sourceRoot, false))
							{
								contentEntry.addSourceFolder(sourceRoot, false, suggestedRoot.getPackagePrefix());
							}
						}
					}
				}
				if (finishRunnable != null)
				{
					finishRunnable.run();
				}
			}
		};

		new SwingWorker()
		{
			@Override
			public Object construct()
			{
				searchRunnable.run();
				return null;
			}

			@Override
			public void finished()
			{
				addSourcesRunnable.run();
			}
		}.start();
	}

	@Override
	protected ContentEntryEditor createContentEntryEditor(final String contentEntryUrl)
	{
		return new JavaContentEntryEditor(contentEntryUrl, getEditHandlers())
		{
			@Override
			protected ModifiableRootModel getModel()
			{
				return PerlContentEntriesEditor.this.getModel();
			}
		};
	}

	@Override
	protected List<ContentEntry> addContentEntries(VirtualFile[] files)
	{
		List<ContentEntry> contentEntries = super.addContentEntries(files);
		if (!contentEntries.isEmpty())
		{
			final ContentEntry[] contentEntriesArray = contentEntries.toArray(new ContentEntry[contentEntries.size()]);
			addSourceRoots(myProject, contentEntriesArray, new Runnable()
			{
				@Override
				public void run()
				{
					addContentEntryPanels(contentEntriesArray);
				}
			});
		}
		return contentEntries;
	}

	@Override
	protected JPanel createBottomControl(Module module)
	{
		if (Registry.is("ide.new.project.settings")) return null;
		final JPanel innerPanel = new JPanel(new GridBagLayout());
		innerPanel.setBorder(BorderFactory.createEmptyBorder(6, 0, 0, 6));
		return innerPanel;
	}
}
